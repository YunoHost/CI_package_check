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

default_ci_user=ynhci

# This script can get as argument the domain for jenkins, the admin password of YunoHost and the type of installation requested.
# Domain for Jenkins
domain=$1
# Admin password of YunoHost
yuno_pwd=$2
# Type of CI to setup.
ci_type=$3
if [ -z "$ci_type" ]
then
	echo "Please choose the type of CI to build"
	echo -e "\t1) Stable only"
	echo -e "\t2) Testing and unstable"
	echo -e "\t3) Dev"
	echo -e "\t4) Next debian"
	read -p "?: " answer
fi
case $answer in
	1) ci_type=Stable ;;
	2) ci_type=Testing_Unstable ;;
	3) ci_type=Dev ;;
	4) ci_type=Next_debian ;;
	*) echo "CI type not defined !"; exit 1
esac

echo_bold () {
	echo -e "\e[1m$1\e[0m"
}

# -----------------------------------------------------------------

function install_dependencies() {

    echo_bold "> Installing dependencies..."
    apt-get update
    apt-get install -y curl wget git python3-pip lynx jq python-xmpp snapd
    
    # Install Package check if it isn't an ARM only CI.
    git clone https://github.com/YunoHost/package_check "./package_check" -b cleanup-3 --single-branch

    # Download the app badges
    ./lib/badges/get_badges.sh

    # Create the directory for logs
    mkdir -p "./logs"

    # XMPP script
    mkdir -p "./xmpp_bot"
    wget https://raw.githubusercontent.com/YunoHost/weblate2xmpp/master/to_room.py -O ./xmpp_bot/
    touch "./xmpp_bot/password"
    chmod 600 "./xmpp_bot/password"
    echo 'python /home/CI_package_check/xmpp_bot/to_room.py "$(cat /home/CI_package_check/xmpp_bot/password)" "$@" apps' \
        > "./xmpp_bot/xmpp_post.sh"
    chmod +x "./xmpp_bot/xmpp_post.sh"
}

function setup_yunohost() {
	
    echo_bold "> Setting up Yunohost..."
    local DIST="buster"
    local INSTALL_SCRIPT="https://install.yunohost.org/$DIST"
    curl $INSTALL_SCRIPT | bash -s -- -a
	
    echo_bold "> Running yunohost postinstall"
	yunohost tools postinstall --domain $domain --password $yuno_pwd
    
    echo_bold "> Create CI user"
    yunohost user create --firstname "$default_ci_user" --mail "$default_ci_user@$domain" --lastname "$default_ci_user" "$default_ci_user" --password $yuno_pwd

    # Idk why this is needed but wokay I guess >_>
    echo -e "\n127.0.0.1 $domain	#CI_APP" >> /etc/hosts
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

    lxd init --auto --storage-backend=btrfs # FIXME : add more than 5GB maybe for the storage

    # ci_user will be the one launching job, gives it permission to run lxd commands
    usermod -a -G lxd $ci_user

    # We need a home for the "su" command later ?
    mkdir -p /home/$ci_user
    chown -R $ci_user /home/$ci_user

    # Stupid hack because somehow ipv6 is interfering
    echo "$(dig +short A devbaseimgs.yunohost.org | tail -n 1) devbaseimgs.yunohost.org" >> /etc/hosts

    su $ci_user -s /bin/bash -c "lxc remote add yunohost https://devbaseimgs.yunohost.org --public"
}

function configure_CI() {
    echo_bold "> Configuring the CI..."
   
    cat > "./config" <<EOF
TIMEOUT=10800
CI_TYPE=$ci_type
CI_USER=$ci_user
CI_URL=$domain/$ci_path
EOF

    # Cron tasks
    if [ $ci_type == "Dev" ]
    then
        cron_file="./lib/cron_dev"
    elif
        cron_file="./lib/cron_yunorunner"
    fi
    cp "$cron_file" "/etc/cron.d/CI_package_check"

    # Add permission to the user for the entire CI_package_check because it'll be the one running the tests (as a non-root user)
    chown -R $ci_user ./
}

# =========================
#  Main stuff
# =========================

install_dependencies

[ -e /usr/bin/yunohost ] || setup_yunohost

if [ $ci_type == "Dev" ]
then
    source setup_jenkins_and_chroot.sh
else
    source setup_yunorunner.sh
fi

setup_lxd
configure_CI

echo "Done!"
echo " "
echo "N.B. : The file ./xmpp_bot/password needs to be provided with the xmpp bot password."
