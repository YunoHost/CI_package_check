#!/bin/bash

cd "$(dirname $(realpath $0))"

if [ $# -ne 2 ]
then
    echo "This script need to take in argument the domain and admin password for the yunohost installation."
    exit 1
fi

if [ $(pwd) != "/home/CI_package_check" ]
then
    echo "CI_package_check should be installed in /home/CI_package_check"
    exit 1
fi


# This script can get as argument the domain for yunorunner, the admin password of YunoHost and the type of installation requested.
domain=$1
yuno_pwd=$2
ci_type=$3
if [ -z "$ci_type" ]
then
	echo "Please choose the type of CI to build"
    echo -e "\t1) Regular (jobs from apps.json, etc..)"
    echo -e "\t2) Dev (jobs from ssh chroots folders)"
	read -p "?: " answer
fi
case $answer in
	1) ci_type=Regular ;;
	2) ci_type=Dev ;;
	*) echo "CI type not defined !"; exit 1
esac

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
    apt-get install -y curl wget git python3-pip lynx jq snapd
    pip3 install xmpppy
    
    # Install Package check if it isn't an ARM only CI.
    git clone https://github.com/YunoHost/package_check "./package_check" -b cleanup-3 --single-branch

    # Download the app badges
    ./lib/get_badges.sh

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
    cat /dev/urandom | tr -dc _A-Za-z0-9 | head -c${1:-80} | tee /var/www/yunorunner/token /var/www/yunorunner/tokens

    # For Dev CI, we want to control the job scheduling entirely
    # (c.f. the scan_for_new_jobs_from_chroots cron job)
    if [ $ci_type == "Dev" ]
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

    echo_bold "> Disabling dnsmasq + allow port 67 on firewall to not interfere with LXD's DHCP"

    systemctl stop dnsmasq
    systemctl disable dnsmasq
    yunohost firewall allow Both 67

    echo_bold "> Installing lxd..."

    snap install core
    snap install lxd

    ln -s /snap/bin/lxc /usr/local/bin/lxc
    ln -s /snap/bin/lxd /usr/local/bin/lxd

    lxd init --auto --storage-backend=dir

    # ci_user will be the one launching job, gives it permission to run lxd commands
    usermod -a -G lxd $ci_user

    # We need a home for the "su" command later ?
    mkdir -p /home/$ci_user
    chown -R $ci_user /home/$ci_user

    su $ci_user -s /bin/bash -c "lxc remote add yunohost https://devbaseimgs.yunohost.org --public"
}

function setup_chrootdirs() {
    # Installation de ssh_chroot_dir
    # FIXME : ain't an issue that the password is empty here ...?
    yunohost app install --force https://github.com/YunoHost-Apps/ssh_chroot_dir_ynh -a "ssh_user=base_user&password=&pub_key=fake_key&size=1G"
}

function configure_CI() {
    echo_bold "> Configuring the CI..."
   
    cat > "./config" <<EOF
TIMEOUT=10800
ARCH=amd64
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
    
    if [ $ci_type == "Dev" ]
    then
    cat >>  "/etc/cron.d/CI_package_check" << EOF
# Vérifie toutes les 1 minutes si une nouvelle app a été ajoutée.
*/1 * * * * root "/home/CI_package_check/lib/dev_ci/scan_for_new_jobs_from_chroots.sh" >> "/home/CI_package_check/lib/dev_ci/scan_for_new_jobs_from_chroots.log" 2>&1
EOF
    fi

    # Add permission to the user for the entire CI_package_check because it'll be the one running the tests (as a non-root user)
    chown -R $ci_user ./
}

# =========================
#  Main stuff
# =========================

install_dependencies

[ -e /usr/bin/yunohost ] || setup_yunohost

setup_yunorunner

[ $ci_type == "Dev" ] && setup_chrootdirs

setup_lxd
configure_CI

echo "Done!"
echo " "
echo "N.B. : The file ./.xmpp_password needs to be provided with the xmpp bot password."
echo ""
echo "When you're ready to start the CI, run:    systemctl restart $ci_user"
