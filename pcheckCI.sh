#!/bin/bash

timeout=7200	# Durée maximale d'exécution de Package_check avant de déclarer un timeout et de stopper le processus.

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

if ! test -e "$script_dir/pcheck_lock"
then	# Le travail est reporté à la prochaine exécution si le lock de package check est présent.
	if test -s "$script_dir/work_list"
	then	# Si la liste de test n'est pas vide
		touch "$script_dir/pcheck_lock"
		APP=$(head -n1 "$script_dir/work_list")
		rm -f "$script_dir/logs/$(basename $APP).log"	# Supprime le log du précédent test.
		inittime=$(date +%s)	# Enregistre l'heure de démarrage du test
		"$script_dir/package_check/package_check.sh" --bash-mode $APP > "$script_dir/package_check/Test_results_cli.log" &	# Exécute package_check sur la première adresse de la liste, et passe l'exécution en arrière plan.
		PID_PCHECK=$!	# Récupère le PID de la commande package_check
		while ps -p $PID_PCHECK | grep -q $PID_PCHECK	# Boucle tant que le process tourne, pour vérifier le temps d'exécution
		do
			if [ $(( $(date +%s) - $inittime )) -ge $timeout ]	# Vérifie la durée d'exécution du test
			then	# Si la durée dépasse le timeout fixé, force l'arrêt du test pour ne pas bloquer la machine
				kill -s 15 $PID_PCHECK	# Demande l'arrêt du script.
				"$script_dir/lxc_stop.sh" # Arrête le conteneur LXC.
				inittime=0	# Indique l'arrêt forcé du script
			fi
			sleep 30
		done
		sed -i 1d "$script_dir/work_list"	# Supprime la première ligne de la liste
		cp "$script_dir/package_check/Test_results_cli.log" "$script_dir/logs/$(basename $APP).log"
		if [ "$inittime" -eq "0" ]; then
			echo "!!! L'exécution de Package_check a été trop longue, le script a été avorté. !!!" >> "$script_dir/logs/$(basename $APP).log"
		fi
		rm "$script_dir/pcheck_lock"
	fi
fi
