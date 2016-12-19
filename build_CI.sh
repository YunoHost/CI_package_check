#!/bin/bash

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

touch "$script_dir/CI.lock"	# Place le lock du CI, pour éviter des démarrages intempestifs avant la fin de l'installation

touch "$script_dir/work_list"	# Créer le fichier work_list
chmod 666 "$script_dir/work_list"	# Et lui donne le droit d'écriture par tout le monde. Car c'est le logiciel de CI qui va y écrire.
mkdir -p "$script_dir/logs"	# Créer le dossier des logs

git clone https://github.com/YunoHost/package_check "$script_dir/package_check"
echo -e "\e[1mBuild du conteneur LXC pour Package check\e[0m"
sudo "$script_dir/package_check/sub_scripts/lxc_build.sh"	# Construit le conteneur LXC pour package_check

sudo cp "$script_dir/CI_package_check_cron" /etc/cron.d/CI_package_check	# Et met en place le cron

sudo sed -i "s@__PATH__@$script_dir@g" "/etc/cron.d/CI_package_check"	# Renseigne l'emplacement du script dans le cron

sudo rm "$script_dir/CI.lock" # Libère le lock du CI
echo -e "\e[1mPackage check est prêt à travailler en CI à partir de la liste de tâche work_list.\e[0m"
