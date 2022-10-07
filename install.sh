#!/bin/bash

cd "$(dirname $(realpath $0))"

if (( $# < 3 ))
then
    cat << EOF
Usage: ./install.sh some.domain.tld SecretAdminPasswurzd! [auto|manual] [cluster]

1st and 2nd arguments are for yunohost postinstall
  - domain
  - admin password

3rd argument is the CI type (scheduling strategy):
  - auto means job will automatically be scheduled by yunorunner from apps.json etc.
  - manual means job will be scheduled manually (e.g. via webhooks or yunorunner ciclic)

4th argument is to build the first node of an lxc cluster
 - lxd cluster will be created with the current server
 - some.domain.tld will be the cluster hostname and SecretAdminPasswurzd! the trust password to join the cluster

EOF
    exit 1
fi

if [ $(pwd) != "/home/CI_package_check" ]
then
    echo "CI_package_check should be installed in /home/CI_package_check"
    exit 1
fi

domain=$1
yuno_pwd=$2
ci_type=$3
lxd_cluster=$4

# User which execute the CI software.
ci_user=yunorunner
# Web path of the CI
ci_path=ci

echo_bold () {
	echo -e "\e[1m$1\e[0m"
}

# -----------------------------------------------------------------

function install_dependencies() {

    echo_bold "> Installing dependencies..."
    apt-get update
    apt-get install -y curl wget git python3-pip lynx jq
    pip3 install xmpppy
    
    git clone https://github.com/YunoHost/package_check "./package_check"

    # Download the app badges
    ./badges/get_badges.sh

    # Create the directory for logs
    mkdir -p "./logs"
}

function setup_yunohost() {
	
    echo_bold "> Setting up Yunohost..."
    local DIST="buster"
    local INSTALL_SCRIPT="https://install.yunohost.org/$DIST"
    curl $INSTALL_SCRIPT | bash -s -- -a
	
    echo_bold "> Running yunohost postinstall"
	yunohost tools postinstall --domain $domain --password $yuno_pwd
    
    # What is it used for :| ...
    echo_bold "> Create Yunohost CI user"
    local ynh_ci_user=ynhci
    yunohost user create --firstname "$ynh_ci_user" --domain "$domain" --lastname "$ynh_ci_user" "$ynh_ci_user" --password $yuno_pwd

    # Idk why this is needed but wokay I guess >_>
    echo -e "\n127.0.0.1 $domain	#CI_APP" >> /etc/hosts

    echo_bold "> Disabling unecessary services to save up RAM"
    for SERVICE in mysql php7.3-fpm metronome rspamd dovecot postfix redis-server postsrsd yunohost-api avahi-daemon
    do
        systemctl stop $SERVICE
        systemctl disable $SERVICE --quiet
    done
}

function setup_yunorunner() {
    echo_bold "> Installation of YunoRunner..."
    yunohost app install --force https://github.com/YunoHost-Apps/yunorunner_ynh -a "domain=$domain&path=/$ci_path"
    port=$(yunohost app setting yunorunner port)

    # Stop YunoRunner
    # to be started manually by the admin after the CI_package_check install
    # finishes
    systemctl stop yunorunner

    # Remove the original database, in order to rebuilt it with the new config.
    rm -f /var/www/yunorunner/db.sqlite

    # Create a random token for ciclic
    cat /dev/urandom | tr -dc _A-Za-z0-9 | head -c80 | tee /var/www/yunorunner/token /var/www/yunorunner/tokens > /dev/null

    # For automatic / "main" CI we want to auto schedule jobs using the app list
    if [ $ci_type == "auto" ]
    then
        cat >/var/www/yunorunner/config.py <<EOF
BASE_URL = "https://$domain/$ci_path"
PORT = $port
PATH_TO_ANALYZER = "/home/CI_package_check/analyseCI.sh"
MONITOR_APPS_LIST = True
MONITOR_GIT = True
MONITOR_ONLY_GOOD_QUALITY_APPS = False
MONTHLY_JOBS = True
WORKER_COUNT = 1
EOF
    # For Dev CI, we want to control the job scheduling entirely
    # (c.f. the github webhooks or scan_for_new_jobs_from_chroots cron job)
    else
        cat >/var/www/yunorunner/config.py <<EOF
BASE_URL = "https://$domain/$ci_path"
PORT = $port
PATH_TO_ANALYZER = "/home/CI_package_check/analyseCI.sh"
MONITOR_APPS_LIST = False
MONITOR_GIT = False
MONITOR_ONLY_GOOD_QUALITY_APPS = False
MONTHLY_JOBS = False
WORKER_COUNT = 1
EOF
    fi

    # Put YunoRunner as the default app on the root of the domain
    yunohost app makedefault -d "$domain" yunorunner
}

function setup_lxd() {
    if ! yunohost app list | grep -q 'id: lxd'; then
        yunohost app install --force https://github.com/YunoHost-Apps/lxd_ynh
    fi

    echo_bold "> Configuring lxd..."

    if [ $lxd_cluster == "cluster" ]
    then
        local free_space=$(df --output=avail / | sed 1d)
        local btrfs_size=$(( $free_space * 90 / 100 / 1024 / 1024 ))
        local lxc_network=$((1 + $RANDOM % 254))

        yunohost firewall allow TCP 8443
        cat >./preseed.conf <<EOF
config:
  cluster.https_address: $domain:8443
  core.https_address: ${domain}:8443
  core.trust_password: ${yuno_pwd}
networks:
- config:
    ipv4.address: 192.168.${lxc_network}.1/24
    ipv4.nat: "true"
    ipv6.address: none
  description: ""
  name: lxdbr0
  type: bridge
  project: default
storage_pools:
- config:
    size: ${btrfs_size}GB
    source: /var/lib/lxd/disks/local.img
  description: ""
  name: local
  driver: btrfs
profiles:
- config: {}
  description: Default LXD profile
  devices:
    lxdbr0:
      nictype: bridged
      parent: lxdbr0
      type: nic
    root:
      path: /
      pool: local
      type: disk
  name: default
projects:
- config:
    features.images: "true"
    features.networks: "true"
    features.profiles: "true"
    features.storage.volumes: "true"
  description: Default LXD project
  name: default
cluster:
  server_name: ${domain}
  enabled: true
EOF
        cat ./preseed.conf | lxd init --preseed
        rm ./preseed.conf
        lxc config set core.https_address [::]
    else
        lxd init --auto --storage-backend=dir
    fi

    # ci_user will be the one launching job, gives it permission to run lxd commands
    usermod -a -G lxd $ci_user

    # We need a home for the "su" command later ?
    mkdir -p /home/$ci_user
    chown -R $ci_user /home/$ci_user

    su $ci_user -s /bin/bash -c "lxc remote add yunohost https://devbaseimgs.yunohost.org --public --accept-certificate"
}

function configure_CI() {
    echo_bold "> Configuring the CI..."
   
    cat > "./config" <<EOF
TIMEOUT=10800
ARCH=$(get_arch)
YNH_BRANCH=stable
CI_TYPE=$ci_type
CI_USER=$ci_user
CI_URL=$domain/$ci_path
EOF

    # Cron tasks
    cat >>  "/etc/cron.d/CI_package_check" << EOF
# self-upgrade every night
0 3 * * * root "/home/CI_package_check/lib/self_upgrade.sh" >> "/home/CI_package_check/lib/self_upgrade.log" 2>&1

# Update app list
0 20 * * 5 root "/home/CI_package_check/lib/update_level_apps.sh" >> "/home/CI_package_check/lib/update_level_apps.log" 2>&1

# Update badges
0 20 * * 5 root "/home/CI_package_check/lib/update_badges.sh" >> "/home/CI_package_check/lib/update_badges.log" 2>&1
EOF
    
    # Add permission to the user for the entire CI_package_check because it'll be the one running the tests (as a non-root user)
    chown -R $ci_user ./
}

#=================================================
# GET HOST ARCHITECTURE
#=================================================

function get_arch()
{
    local architecture
    if uname -m | grep -q "arm64" || uname -m | grep -q "aarch64"; then
        architecture="arm64"
    elif uname -m | grep -q "64"; then
        architecture="amd64"
    elif uname -m | grep -q "86"; then
        architecture="i386"
    elif uname -m | grep -q "arm"; then
        architecture="armhf"
    else
        architecture="unknown"
    fi
    echo $architecture
}

# =========================
#  Main stuff
# =========================

install_dependencies

[ -e /usr/bin/yunohost ] || setup_yunohost

setup_yunorunner
setup_lxd
configure_CI

echo "Done!"
echo " "
echo "N.B. : The file ./.xmpp_password needs to be provided with the xmpp bot password to enable notifications."
echo "You may also want to tweak the 'config' file to run test with a different branch / arch"
echo ""
echo "When you're ready to start the CI, run:    systemctl restart $ci_user"
