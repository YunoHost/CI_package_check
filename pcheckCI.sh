#!/bin/bash

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

timeout=$(grep "timeout=" "$script_dir/config" | cut -d= -f2)	# Durée maximale d'exécution de Package_check avant de déclarer un timeout et de stopper le processus.

PCHECK_LOCAL () {
	echo -n "Exécution du test en local"
	if [ -n "$ARCH" ]; then
		echo " pour l'architecture $ARCH."
	else
		echo "."
	fi
	"$script_dir/package_check/package_check.sh" --bash-mode "$APP" &	# Exécute package_check depuis le sous-dossier local
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
	cp "$script_dir/package_check/Complete.log" "$script_dir/logs/$complete_log"	# Copie le log complet
}

PCHECK_SSH () {
	echo "Exécution du test sur $ssh_host pour l'architecture $ARCH"
	echo "Connection ssh initiale"
	ssh $ssh_user@$ssh_host -p $ssh_port -i "$ssh_key" "exit"	# Initie une première connection pour tester ssh
	if [ "$?" -ne 0 ]; then
		echo "Échec de connexion ssh"
	else
		ssh $ssh_user@$ssh_host -p $ssh_port -i "$ssh_key" "\"$pcheckci_path/analyseCI.sh\" \"$APP\" \"$job\"" | tee "$script_dir/package_check/Complete.log"	# Exécute package_check via ssh sur la machine distante et redirige la sortie sur le log de package_check pour leurrer analyseCI afin d'avoir la progression des tests.
		scp -P $ssh_port -i "$ssh_key" $ssh_user@$ssh_host:"$pcheckci_path/package_check/Complete.log" "$script_dir/logs/$complete_log"	# Copie le log complet
	fi
}

EXEC_PCHECK () {	# Démarre les tests en fonction de l'architecture demandée.
	if [ "$ARCH" = "~x86-64b~" ]
	then
		arch_pre=64
	elif [ "$ARCH" = "~x86-32b~" ]
	then
		arch_pre=32
	elif [ "$ARCH" = "~ARM~" ]
	then
		arch_pre=arm
	else	# Par défaut, utilise l'instance locale. Si aucune architecture n'est mentionnée.
		arch_pre=none
	fi
	if [ "$arch_pre" != "none" ]; then	# Si l'architecture est précisée, cherche dans le fichier de config le type d'instance à utiliser.
		instance=$(grep "> $arch_pre.Instance=" "$script_dir/config" | cut -d= -f2)	# Récupère l'instance, LOCAL ou SSH pour l'architecture
	fi
	if [ "$instance" = "SSH" ]
	then # Si l'instance pour l'archi est configurée sur SSH
		ssh_host=$(grep "> $arch_pre.ssh_host=" "$script_dir/config" | cut -d= -f2)	# Récupère le nom de domaine ou l'IP de la machine distante
		ssh_user=$(grep "> $arch_pre.ssh_user=" "$script_dir/config" | cut -d= -f2)	# Récupère le nom de l'utilisateur autorisé à se connecté avec la clé ssh
		ssh_key=$(grep "> $arch_pre.ssh_key=" "$script_dir/config" | cut -d= -f2)	# Récupère l'emplacement de la clé privée pour la connexion ssh
		pcheckci_path=$(grep "> $arch_pre.pcheckci_path=" "$script_dir/config" | cut -d= -f2)	# Récupère l'emplacement de analyseCI.sh sur la machine distante depuis ssh.
		ssh_port=$(grep "> $arch_pre.ssh_port=" "$script_dir/config" | cut -d= -f2)	# Récupère le port ssh
		PCHECK_SSH	# Démarre le test via ssh
	else
		PCHECK_LOCAL	# Démarre le test en local
	fi
}

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
	job=$(echo $APP | cut -d ';' -f 3)	# Isole le nom du test
	APP=$(echo $APP | cut -d ';' -f 1)	# Isole l'app
	ARCH="$(echo $(expr match "$job" '.*\((~.*~)\)') | cut -d'(' -f2 | cut -d')' -f1)"	# Isole le nom de l'architecture après le nom du test.

	if echo "$job" | grep -q "(testing)"	# Vérifie si c'est un test testing
	then
		echo "Test sur instance testing"
		log_dir="logs_testing/"
		"$script_dir/auto_build/switch_container.sh" testing
	elif echo "$job" | grep -q "(unstable)"	# Vérifie si c'est un test unstable
	then
		echo "Test sur instance unstable"
		log_dir="logs_unstable/"
		"$script_dir/auto_build/switch_container.sh" unstable
	else	# stable
		echo "Test sur instance stable"
		"$script_dir/auto_build/switch_container.sh" stable
		log_dir=""
	fi

	echo $id > "$script_dir/CI.lock" # Met en place le lock pour le CI, afin d'éviter des démarrages pendant les wait. Le lock contient le nom du package à tester
	chmod 666 "$script_dir/CI.lock"	# Donne le droit au script analyseCI de modifier le lock.
	date
	echo "Un test avec Package check va démarrer sur $APP (id: $id)"
	APP_LOG=${log_dir}$(echo "${APP#http*://}" | sed 's@/@_@g')$ARCH.log # Supprime http:// ou https:// au début et remplace les / par des _. Ceci sera le fichier de log de l'app.
	complete_log=${log_dir}$(basename -s .log "$APP_LOG")_complete.log	# Le complete log est le même que celui des résultats, auquel on ajoute _complete avant le .log
	rm -f "$script_dir/logs/$APP_LOG"	# Supprime le log du précédent test.
	inittime=$(date +%s)	# Enregistre l'heure de démarrage du test
	EXEC_PCHECK > "$script_dir/package_check/Test_results_cli.log" 2>&1	# Lance l'exécution de package_check en fonction de l'architecture processeur indiquée.

	sed -i 1d "$script_dir/work_list"	# Supprime la première ligne de la liste
	echo -n "Le log complet pour cette application a été dupliqué et est accessible à l'adresse " >> "$script_dir/package_check/Test_results_cli.log"
	if test -e "$script_dir/auto_build/auto.conf"	# Si le fichier de conf de auto_build existe, c'est une instance avec accès en ligne aux logs
	then
		DOMAIN=$(cat "$script_dir/auto_build/auto.conf" | grep DOMAIN= | cut -d '=' -f2)
		CI_PATH=$(cat "$script_dir/auto_build/auto.conf" | grep CI_PATH= | cut -d '=' -f2)
		echo "https://$DOMAIN/$CI_PATH/logs/$complete_log" >> "$script_dir/package_check/Test_results_cli.log"
	else
		echo "$script_dir/logs/$complete_log" >> "$script_dir/package_check/Test_results_cli.log"
	fi
	if [ "$inittime" -eq "0" ]; then
		echo "!!! L'exécution de Package_check a été trop longue, le script a été avorté. !!! (PCHECK_AVORTED)" >> "$script_dir/package_check/Test_results_cli.log"
	fi
	cp "$script_dir/package_check/Test_results_cli.log" "$script_dir/logs/$APP_LOG"	# Copie le log des résultats
	sed -i "1i-> Test $job\n" "$script_dir/logs/$APP_LOG"	# Ajoute le nom du job au début du log
	date
	echo "Fin du test sur $APP (id: $id)"
	inittime=$(date +%s)	# Enregistre l'heure de démarrage de la boucle
	while test -s "$script_dir/CI.lock"; do
		if [ $(( $(date +%s) - $inittime )) -ge $timeout ]	# Vérifie la durée de la boucle
		then
			echo "Libération forcée du lock du CI"
			break;	# Si la durée dépasse le timeout fixé, force l'arrêt du test pour ne pas bloquer la machine
		fi
		sleep 5	# Attend la fin du script analyseCI. Signalé par le vidage du fichier CI.lock
	done
	rm "$script_dir/CI.lock" # Libère le lock du CI
	date
	echo -e "Lock libéré pour $APP (id: $id)\n"
	echo "\"$script_dir/auto_build/compare_level.sh\" \"$job\" \"$APP_LOG\" > \"$script_dir/auto_build/compare_level.log\" 2>&1" | at now + 5 min	# Diffère la notation du niveau de l'app, ou sa comparaison. (Le différer permet de démarrer un autre test le cas échéant.)
	echo "\"$script_dir/auto_build/compare_level.sh\" \"$job\" \"$APP_LOG\" > \"$script_dir/auto_build/compare_level.log\" 2>&1"
fi
