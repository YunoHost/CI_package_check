#!/bin/bash

script_dir="$(dirname $(realpath $0))"

# Add the directory for official branches
mkdir -p "/home/yunohost.app/ssh_chroot_directories/Official/data"

# Add the cron task for official branches
cat "$script_dir/CI_package_check_cron_branch" | sudo tee -a "/etc/cron.d/CI_package_check" > /dev/null	# Ajoute le cron à la suite du cron de CI déjà en place.
sudo sed -i "s@__PATH__@$script_dir@g" "/etc/cron.d/CI_package_check"	# Renseigne l'emplacement du script dans le cron
