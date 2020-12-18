#/bin/bash

# Récupère le dossier du script
if [ "$(echo "$0" | cut -c1)" = "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

SCALEWAY_SHUTDOWN () {
	"$script_dir/scaleway_api.sh" stop
}

SHUTDOWN () {
	SCALEWAY_SHUTDOWN
}

idleCI=1

date
while [ $idleCI -ne 0 ] && [ $idleCI -ne 3 ]
do	# La boucle vérifie 3 fois que le serveur est inactif
	sleep 540	# Patiente 9 min avant chaque vérification.
	if [ -e "$script_dir/lock_shutdown.on" ]; then
		echo "lock_shutdown.on"
		idleCI=0	# Si le fichier lock_shutdown.on est présent, arrêt annulé.
	fi

	if [ -s "$script_dir/../work_list" ]; then
		echo "work_list pas vide"
		idleCI=0	# Si la work_list n'est pas vide, arrêt annulé.
	fi

    # FIXME
	LXC_NAME=$(cat "$script_dir/../package_check/config" | grep LXC_NAME= | cut -d '=' -f2)
	if [ $(sudo lxc info $LXC_NAME | grep -c "STOPPED") -eq 0 ]; then
		echo "Conteneur en cours d'exécution"
		idleCI=0	# Si le conteneur n'est pas stoppé, arrêt annulé.
	fi
	if [ $idleCI -ne 0 ]; then
		echo "OK"
		idleCI=$(expr $idleCI + 1)  # Si l'arrêt n'est pas invalidé, incrémente idleCI de 1.
	fi
done

if [ $idleCI -eq 3 ]; then
	echo "Shutdown"
	SHUTDOWN	# Si après 3 vérifications le serveur était toujours inactif, arrêt du serveur.
fi
