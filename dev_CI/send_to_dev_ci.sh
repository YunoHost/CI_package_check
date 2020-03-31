#!/bin/bash

folder="$1"
ssh_user=USER_NAME
ssh_host=ci-apps-dev.yunohost.org
ssh_port=22
ssh_key=~/.ssh/PRIVATE_KEY
distant_dir=/data
SSHSOCKET=~/.ssh/ssh-socket-%r-%h-%p

if [[ -z "$folder" ]]
then
    echo "Usage: ./send_to_dev_ci.sh appfolder_ynh/"
fi

echo "Opening connection"
ssh $ssh_user@$ssh_host -p $ssh_port -i $ssh_key -f -M -N -o ControlPath=$SSHSOCKET	# Créé une connection ssh maître.
if [ "$?" -ne 0 ]; then	# Si l'utilisateur tarde trop, la connexion sera refusée...
	ssh $ssh_user@$ssh_host -p $ssh_port -i $ssh_key -f -M -N -o ControlPath=$SSHSOCKET	# Créé une connection ssh maître.
fi

rsync -avzhuE -c --progress --delete --exclude="/.git/" "$folder" -e "ssh -i $ssh_key -p $ssh_port -o ControlPath=$SSHSOCKET"  $ssh_user@$ssh_host:"$distant_dir/"

echo "Closing connection"
ssh $ssh_user@$ssh_host -p $ssh_port -i $ssh_key -S $SSHSOCKET -O exit

echo "============================"
echo "Build should show up here once it starts:"
echo "https://$ssh_host/jenkins/view/$ssh_user/job/$folder%20($ssh_user)/lastBuild/console"

