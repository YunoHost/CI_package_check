#!/bin/bash

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

touch "$script_dir/work_list"	# Créer le fichier work_list
chmod 666 "$script_dir/work_list"	# Et lui donne le droit d'écriture par tout le monde. Car c'est le logiciel de CI qui va y écrire.
mkdir "$script_dir/logs"	# Créer le dossier des logs

git clone https://github.com/YunoHost/package_check "$script_dir/"
echo "Build du conteneur LXC pour Package check"
sudo "$script_dir/package_check/sub_scripts/lxc_build.sh"	# Construit le conteneur LXC pour package_check

sed -i "s@__PATH__@$script_dir@g" "$script_dir/CI_package_check_cron"	# Renseigne l'emplacement du script dans le cron

sudo cp "$script_dir/CI_package_check_cron" /etc/cron.d/	# Et met en place le cron

echo "Package check est prêt à travailler en CI à partir de la liste de tâche work_list."
