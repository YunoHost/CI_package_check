#!/bin/bash

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

ssh_user=SSH_USER
ssh_host=SSH_HOST
ssh_port=22
distant_dir=/home
SSHSOCKET=~/.ssh/ssh-socket-%r-%h-%p

ENVOI_CI () {
	echo ">>> Copie de $1"
	rsync -avzhuE --progress --delete --exclude="^.git.*" "$1" -e "ssh -p $ssh_port -o ControlPath=$SSHSOCKET" $ssh_user@$ssh_host:"$distant_dir/"
}

## Options rsync:
# -a archive (rlptgoD)
# -v verbose
# --delete, supprime les fichiers absent dans la source
# -b backup
# -z compression des données pour le transfert
# -h human readable
# --progress
# -u update, ne remplace pas un fichier si il est plus récent que la source
# -e ssh login@serveur_ip_ou_nom: 	pour utiliser ssh
# -E preserve executability

"$script_dir/scaleway_api.sh" start	# Démarre le serveur scaleway distant avant de se connecter
sleep 3

echo "Connection ssh initiale"
ssh $ssh_user@$ssh_host -p $ssh_port -f -M -N -o ControlPath=$SSHSOCKET	# Créé une connection ssh maître.
if [ "$?" -ne 0 ]; then	# Si l'utilisateur tarde trop, la connexion sera refusée...
	ssh $ssh_user@$ssh_host -p $ssh_port -f -M -N -o ControlPath=$SSHSOCKET	# Créé une connection ssh maître.
fi

ENVOI_CI DOSSIER_DE_MON_APP_1
ENVOI_CI DOSSIER_DE_MON_APP_2

echo "Fermeture de la connection ssh maître."
ssh $ssh_user@$ssh_host -p $ssh_port -S $SSHSOCKET -O exit
