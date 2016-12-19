#!/bin/bash

# Supprime jenkins et package check, ainsi que le cron qui va avec.
# Mais ne supprime pas Yunohost.

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

# JENKINS
REMOVE_JENKINS () {
	echo -e "\e[1mSuppression de jenkins\e[0m"
	sudo yunohost app remove jenkins
	sudo rm "$script_dir/jenkins/jenkins_key" "$script_dir/jenkins/jenkins_key.pub"	# Supprime les clés ssh
}
# / JENKINS

REMOVE_CI_APP () {
	# Suppression du logiciel de CI
	# Pour changer de logiciel, ajouter simplement une fonction et changer l'appel qui suit.
	REMOVE_JENKINS
}

# Suppression du logiciel de CI
REMOVE_CI_APP

echo -e "\e[1mSuppression de Package check\e[0m"
sudo "$script_dir/../package_check/sub_scripts/lxc_remove.sh"

echo -e "\e[1mSuppression des listes de job jenkins\e[0m"
touch "$script_dir/community_app"
touch "$script_dir/official_app"

echo -e "\e[1mSuppression du cron de CI\e[0m"
sudo rm /etc/cron.d/CI_package_check

echo -e "\e[1mRetire les locks\e[0m"
sudo rm "$script_dir/../package_check/pcheck.lock"
sudo rm "$script_dir/../CI.lock"

# Clean hosts
sudo sed -i '/#CI_APP/d' /etc/hosts
