#!/bin/bash

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

echo -e "\e[1mSupprime Package check\e[0m"
sudo "$script_dir/package_check/sub_scripts/lxc_remove.sh"

sudo rm /etc/cron.d/CI_package_check
