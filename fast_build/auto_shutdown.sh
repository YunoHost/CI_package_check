#/bin/bash

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

SCALEWAY_SHUTDOWN () {
	scaleway_api.sh stop
}

SHUTDOWN () {
	SCALEWAY_SHUTDOWN
}

idleCI=1

while [ $idleCI -ne 0 ] || [ $idleCI -ne 3 ]
do	# La boucle vérifie 3 fois que le serveur est inactif
	sleep 180	# Patiente 3 min avant chaque vérification.
	if [ -s ../work_list ]; then
		idleCI=0	# Si la work_list n'est pas vide, arrêt annulé.
	fi

	LXC_NAME=$(cat "$script_dir/../package_check/config" | grep LXC_NAME= | cut -d '=' -f2)
	if [ $(sudo lxc-info --name $LXC_NAME | grep -c "STOPPED") -eq 0 ]; then
		idleCI=0	# Si le conteneur n'est pas stoppé, arrêt annulé.
	fi
	if [ $idleCI -ne 0 ]; then
		(( idleCI++ ))	# Si l'arrêt n'est pas invalidé, incrémente idleCI de 1.
	fi
done

if [ $idleCI -eq 3 ]; then
	SHUTDOWN	# Si après 3 vérifications le serveur était toujours inactif, arrêt du serveur.
fi
