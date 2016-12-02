#!/bin/bash

timeout=7200	# Durée maximale d'exécution de Package_check avant de déclarer un timeout et de stopper le processus.

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

if test -s "$script_dir/work_list"
then	# Si la liste de test n'est pas vide
	if test -e "$script_dir/package_check/pcheck.lock" || test -e "$script_dir/CI.lock"
	then	# Le travail est reporté à la prochaine exécution si le lock de package check est présent ou celui du CI.
		date
		if test -e "$script_dir/package_check/pcheck.lock"; then
			echo "Le fichier $script_dir/package_check/pcheck.lock est présent. Package check est déjà utilisé."
		fi
		if test -e "$script_dir/CI.lock"; then
			echo "Le fichier $script_dir/CI.lock est présent. Un test est déjà en cours."
		fi
		echo "Exécution annulée..."
		exit 0
	fi

	APP=$(head -n1 "$script_dir/work_list")	# Prend la première ligne de work_list
	id=$(echo $APP | cut -d ';' -f 2)	# Isole l'id
	APP=$(echo $APP | cut -d ';' -f 1)	# Isole l'app

	echo $id > "$script_dir/CI.lock" # Met en place le lock pour le CI, afin d'éviter des démarrages pendant les wait. Le lock contient le nom du package à tester
	chmod 666 "$script_dir/CI.lock"	# Donne le droit au script analyseCI de modifier le lock.
	date
	echo "Un test avec Package check va démarrer sur $APP (id: $id)"
	APP_LOG=$(echo "${APP#http*://}" | sed 's@/@_@g').log # Supprime http:// ou https:// au début et remplace les / par des _. Ceci sera le fichier de log de l'app.
	rm -f "$script_dir/logs/$APP_LOG"	# Supprime le log du précédent test.
	inittime=$(date +%s)	# Enregistre l'heure de démarrage du test
	"$script_dir/package_check/package_check.sh" --bash-mode $APP > "$script_dir/package_check/Test_results_cli.log" 2>&1 &	# Exécute package_check sur la première adresse de la liste, et passe l'exécution en arrière plan.
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
	cp "$script_dir/package_check/Test_results_cli.log" "$script_dir/logs/$APP_LOG"	# Copie le log des résultats
	complete_log=$(basename -s .log $APP_LOG)_complete.log	# Le complete log est le même que celui des résultats, auquel on ajoute _complete avant le .log
	cp "$script_dir/package_check/Complete.log" "$script_dir/logs/$complete_log"	# Et le log complet
	sed -i "s@$script_dir/package_check/Complete.log@$script_dir/logs/$complete_log@g" "$script_dir/logs/$APP_LOG"	# Change l'emplacement du complete.log à la fin des résultats du test.
	if [ "$inittime" -eq "0" ]; then
		echo "!!! L'exécution de Package_check a été trop longue, le script a été avorté. !!!" >> "$script_dir/logs/$APP_LOG"
	fi
	date
	echo "Fin du test sur $APP (id: $id)"
	while test -s "$script_dir/CI.lock"; do
		sleep 5	# Attend la fin du script analyseCI. Signaler par le vidage du fichier CI.lock
	done
	rm "$script_dir/CI.lock" # Libère le lock du CI
	date
	echo -e "Lock libéré pour $APP (id: $id)\n"
fi
