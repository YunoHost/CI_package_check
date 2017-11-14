#!/bin/bash

# Récupère le dossier du script
script_dir="$(dirname $(realpath $0))"

ssh_user=USER_NAME
ssh_host=ci-apps-dev.yunohost.org
ssh_port=22
ssh_key=~/.ssh/PRIVATE_KEY
distant_dir=/data
SSHSOCKET=~/.ssh/ssh-socket-%r-%h-%p

ENVOI_CI () {
	echo ">>> Copie de $1"
	rsync -avzhuE -c --progress --delete --exclude="/.git/" "$1" -e "ssh -i $ssh_key -p $ssh_port -o ControlPath=$SSHSOCKET"  $ssh_user@$ssh_host:"$distant_dir/"
}

echo -en "\a"
echo "Connection ssh initiale"
ssh $ssh_user@$ssh_host -p $ssh_port -i $ssh_key -f -M -N -o ControlPath=$SSHSOCKET	# Créé une connection ssh maître.
if [ "$?" -ne 0 ]; then	# Si l'utilisateur tarde trop, la connexion sera refusée...
	ssh $ssh_user@$ssh_host -p $ssh_port -i $ssh_key -f -M -N -o ControlPath=$SSHSOCKET	# Créé une connection ssh maître.
fi

ENVOI_CI APP1
ENVOI_CI APP2
ENVOI_CI APP3...

echo "Fermeture de la connection ssh maître."
ssh $ssh_user@$ssh_host -p $ssh_port -i $ssh_key -S $SSHSOCKET -O exit
