#!/bin/bash

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

if test -e "$script_dir/../package_check/pcheck.lock"
then	# Le switch est annulé
	echo "Le fichier $script_dir/../package_check/pcheck.lock est présent. Package check est déjà utilisé. Changement de conteneur annulé..."
	exit 1
fi

LXC_NAME=$(cat "$script_dir/../package_check/config" | grep LXC_NAME= | cut -d '=' -f2)

type=$1

if [ -h /var/lib/lxcsnaps/$LXC_NAME ]
then	# Si le dossier du snapshot est un lien symbolique
	if ! sudo ls -l /var/lib/lxcsnaps/pchecker_lxc | grep -q "_$type"
	then	# Si le lien ne pointe pas sur le bon snapshot
		echo "> Changement de conteneur vers $type"
		sudo rm /var/lib/lxcsnaps/$LXC_NAME
		sudo ln -sf /var/lib/lxcsnaps/pcheck_$type /var/lib/lxcsnaps/$LXC_NAME
	fi
fi
