#!/bin/bash

cd "$(dirname $(realpath $0))"

if [ $# -ne 3 ]
then
    cat << EOF
Usage: ./install.sh some.domain.tld SecretAdminPasswurzd! [auto|manual]

1st and 2nd arguments are for yunohost postinstall
  - domain
  - admin password

3rd argument is the CI type (scheduling strategy):
  - auto means job will automatically be scheduled by yunorunner from apps.json etc.
  - manual means job will be scheduled manually (e.g. via webhooks or yunorunner ciclic)

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
    yunohost user create --firstname "$ynh_ci_user" --mail "$ynh_ci_user@$domain" --lastname "$ynh_ci_user" "$ynh_ci_user" --password $yuno_pwd

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
    yunohost app install --force https://github.com/YunoHost-Apps/yunorunner_ynh_core -a "domain=$domain&path=/$ci_path"

    # Stop YunoRunner
    # to be started manually by the admin after the CI_package_check install
    # finishes
    systemctl stop yunorunner

    # Remove the original database, in order to rebuilt it with the new config.
    rm -f /var/www/yunorunner/db.sqlite

    # Create a random token for ciclic
    cat /dev/urandom | tr -dc _A-Za-z0-9 | head -c80 | tee /var/www/yunorunner/token /var/www/yunorunner/tokens > /dev/null

    # For Dev CI, we want to control the job scheduling entirely
    # (c.f. the scan_for_new_jobs_from_chroots cron job)
    if [ $ci_type == "manual" ]
    then
        # Ideally this could be handled via a config file in yunorunner rather
        # than having to tweak the systemd service ...
        sed -i "s/^ExecStart.*/& --dont-monitor-apps-list --dont-monitor-git --no-monthly-jobs/" /etc/systemd/system/yunorunner.service
        systemctl daemon-reload
    fi

    # Put YunoRunner as the default app on the root of the domain
    yunohost app makedefault -d "$domain" yunorunner
}

function setup_lxd() {

    local go_version="1.15.8"
    local lxd_version="4.10"

    echo_bold "> Configure dnsmasq + allow port 67 on firewall to not interfere with LXD's DHCP"

    echo "bind-interfaces
except-interface=lxdbr0" > /etc/dnsmasq.d/lxd
    yunohost firewall allow Both 67
    systemctl restart dnsmasq

    echo_bold "> Installing go..."

    # Use the right go architecture.
    local arch=get_arch
    if [ "$arch" = "armhf" ]; then
        arch="armv6l"
    elif [ "$arch" = "aarch64" ]; then
        arch="arm64"
    fi

    wget https://golang.org/dl/go$go_version.linux-$arch.tar.gz -O /tmp/go$go_version.linux-$arch.tar.gz 2>/dev/null
    tar -C /opt/ -xzf /tmp/go$go_version.linux-$arch.tar.gz
    
    export PATH=/opt/go/bin:$PATH

    echo_bold "> Installing lxd dependencies..."

    apt install -y acl autoconf dnsmasq-base git libacl1-dev libcap-dev liblxc1 lxc-dev libsqlite3-dev libtool libudev-dev libuv1-dev make pkg-config rsync squashfs-tools tar tcl xz-utils ebtables libapparmor-dev libseccomp-dev libcap-dev

    echo_bold "> Building lxd..."

    local lxd_path="/opt/lxd-${lxd_version}"
    wget https://github.com/lxc/lxd/releases/download/lxd-${lxd_version}/lxd-${lxd_version}.tar.gz -O /tmp/lxd-${lxd_version}.tar.gz 2>/dev/null
    tar -C /opt/ -xzf /tmp/lxd-${lxd_version}.tar.gz

    export GOPATH=${lxd_path}/_dist

    pushd ${lxd_path}
    make deps
    export CGO_CFLAGS="-I${GOPATH}/deps/raft/include/ -I${GOPATH}/deps/dqlite/include/"
    export CGO_LDFLAGS="-L${GOPATH}/deps/raft/.libs -L${GOPATH}/deps/dqlite/.libs/"
    export LD_LIBRARY_PATH="${GOPATH}/deps/raft/.libs/:${GOPATH}/deps/dqlite/.libs/"
    export CGO_LDFLAGS_ALLOW="-Wl,-wrap,pthread_create"
    cd $GOPATH/src/github.com/lxc/lxd
    make

    mkdir -p /usr/local/lib/lxd
    cp -a ${GOPATH}/deps/{raft,dqlite}/.libs/lib*.so* /usr/local/lib/lxd/
    cp ${GOPATH}/bin/{lxc,lxd} /usr/local/bin
    echo "/usr/local/lib/lxd/" > /etc/ld.so.conf.d/lxd.conf
    ldconfig

    echo "[Unit]
Description=LXD Container Hypervisor
After=network-online.target
Requires=network-online.target lxd.socket
Documentation=man:lxd(1)

[Service]
Environment=LXD_OVMF_PATH=/usr/share/ovmf/x64
ExecStart=/usr/local/bin/lxd --group=lxd --logfile=/var/log/lxd/lxd.log
ExecStartPost=/usr/local/bin/lxd waitready --timeout=600
ExecStop=/usr/local/bin/lxd shutdown
TimeoutStartSec=600s
TimeoutStopSec=30s
Restart=on-failure
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
Delegate=yes
KillMode=process

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/lxd.service

    echo "[Unit]
Description=LXD - unix socket

[Socket]
ListenStream=/var/lib/lxd/unix.socket
SocketMode=0660
SocketGroup=lxd
Service=lxd.service

[Install]
WantedBy=sockets.target" > /etc/systemd/system/lxd.socket

    echo "root:1000000:65536" | sudo tee -a /etc/subuid /etc/subgid

    groupadd lxd

    mkdir -p /var/log/lxd

    systemctl daemon-reload
    systemctl enable --now lxd
    popd
    rm -r /opt/go ${lxd_path}

    echo_bold "> Configuring lxd..."

    lxd init --auto --storage-backend=dir

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
        architecture="aarch64"
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
