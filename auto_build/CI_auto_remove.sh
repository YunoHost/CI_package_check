#!/bin/bash

# Remove jenkins, package check and the cron
# But keep YunoHost

# Get the path of this script
script_dir="$(dirname $(realpath $0))"

# SPECIFIC PART FOR JENKINS (START)
REMOVE_JENKINS () {
	echo -e "\e[1mDeletion of jenkins\e[0m"
	sudo yunohost app remove jenkins
	# Remove the ssh keys
	sudo rm "$script_dir/jenkins/jenkins_key" "$script_dir/jenkins/jenkins_key.pub"
	sudo rm -rf /var/lib/jenkins

	domain=$(grep DOMAIN= "$script_dir/auto.conf" | cut -d= -f2)
	sudo sed -i "/$domain/d" /root/.ssh/known_hosts
}
# SPECIFIC PART FOR JENKINS (END)

# SPECIFIC PART FOR YUNORUNNER (START)
REMOVE_YUNORUNNER () {
	echo -e "\e[1mDeletion of YunoRunner\e[0m"
	sudo yunohost app remove yunorunner
}
# SPECIFIC PART FOR YUNORUNNER (END)

REMOVE_CI_APP () {
	# Deletion of the CI front end
# 	REMOVE_JENKINS
 	REMOVE_YUNORUNNER
}

REMOVE_CI_APP

echo -e "\e[1mRemove package check\e[0m"
sudo "$script_dir/../package_check/sub_scripts/lxc_remove.sh"

echo -e "\e[1mRemove jobs list\e[0m"
rm "$script_dir/community_app" "$script_dir/official_app"
touch "$script_dir/community_app"
touch "$script_dir/official_app"

echo -e "\e[1mRemove the cron file\e[0m"
sudo rm /etc/cron.d/CI_package_check

echo -e "\e[1mRemove the lock files\e[0m"
sudo rm "$script_dir/../package_check/pcheck.lock"
sudo rm "$script_dir/../CI.lock"

# Clean hosts
sudo sed -i '/#CI_APP/d' /etc/hosts

# Clean LXC
echo -e "\e[1mRemove the LXC containers and snapshots\e[0m"

lxc_name=$(grep LXC_NAME= "$script_dir/../package_check/config" | cut -d '=' -f2)

if [ -n "$lxc_name" ]; then
	sudo rm -rf /var/lib/lxc/$lxc_name
	sudo rm -f /var/lib/lxcsnaps/$lxc_name
fi
sudo rm -rf /var/lib/lxcsnaps/pcheck_stable
sudo rm -rf /var/lib/lxcsnaps/pcheck_testing
sudo rm -rf /var/lib/lxcsnaps/pcheck_unstable
