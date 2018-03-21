#!/bin/bash

# Install Package check and configure it to be used by a CI software

# Get the path of this script
script_dir="$(dirname $(realpath $0))"

ci_frontend=jenkins


# Install git and at
sudo apt-get update > /dev/null
sudo apt-get install -y git at

# Set a lock file to prevent any start fo the CI during the install process.
touch "$script_dir/CI.lock"

# Create the work_list file
touch "$script_dir/work_list"
# And allow avery one to write into it. To allow the CI software to write.
chmod 666 "$script_dir/work_list"
# Create the directory for logs
mkdir -p "$script_dir/logs"

# Install Package check if it isn't an ARM only CI.
if [ "$(grep CI_TYPE "$script_dir/auto_build/auto.conf" | cut -d '=' -f2)" 2> /dev/null != "ARM" ]
then
	git clone https://github.com/YunoHost/package_check "$script_dir/package_check"
	echo -e "\e[1mBuild the LXC container for Package check\e[0m"
	sudo "$script_dir/package_check/sub_scripts/lxc_build.sh"
fi

# Set the cron file
sudo cp "$script_dir/CI_package_check_cron" /etc/cron.d/CI_package_check
sudo sed -i "s@__PATH__@$script_dir@g" "/etc/cron.d/CI_package_check"

# Build a config file
cp "$script_dir/config.modele" "$script_dir/config"

# Get the url of the front end CI
ci_url=$(sudo yunohost app map | grep $ci_frontend -m1 | cut -d: -f1)
# Then add it to the config file
sed -i "s@CI_URL=@&$ci_url@g" "$script_dir/config"

# Remove the lock file
sudo rm "$script_dir/CI.lock"
echo -e "\e[1mPackage check is ready to work as a CI with the work_list file.\e[0m"
