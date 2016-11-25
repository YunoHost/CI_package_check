#!/bin/bash

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

if ! test -e "$script_dir/pcheck_lock"
then	# Le travail est reporté à la prochaine exécution si le lock de package check est présent.
	if test -s "$script_dir/work_list"
	then	# Si la liste de test n'est pas vide
		touch "$script_dir/pcheck_lock"
		APP=$(head -n1 "$script_dir/work_list")
		rm "$script_dir/logs/$(basename $APP).log"	# Supprime le log du précédent test.
		"$script_dir/package_check/package_check.sh" --bash-mode $APP	# Exécute package_check sur la première adresse de la liste.
		sed -i 1d "$script_dir/work_list"	# Supprime la première ligne de la liste
		cp "$script_dir/package_check/Test_results.log" "$script_dir/logs/$(basename $APP).log"
		rm "$script_dir/pcheck_lock"
	fi
fi
