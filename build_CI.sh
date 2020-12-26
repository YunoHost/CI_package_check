#!/bin/bash

# Install Package check and configure it to be used by a CI software

# Get the path of this script
script_dir="$(dirname $(realpath $0))"

# Install git and at
sudo apt-get update > /dev/null
sudo apt-get install -y git at lxd snapd 

# Create the directory for logs
mkdir -p "$script_dir/logs"

# Install Package check if it isn't an ARM only CI.
git clone https://github.com/YunoHost/package_check "$script_dir/package_check" -b cleanup-3 --single-branch

# Set the cron file
sudo cp "$script_dir/CI_package_check_cron" /etc/cron.d/CI_package_check
sudo sed -i "s@__PATH__@$script_dir@g" "/etc/cron.d/CI_package_check"

# Build a config file
cp "$script_dir/config.modele" "$script_dir/config"
