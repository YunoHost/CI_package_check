#!/bin/bash

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

dest=$(cat "$script_dir/auto.conf" | grep MAIL_DEST= | cut -d '=' -f2)

sudo rm -r "$script_dir/../../apps"	# Supprime le précédent clone de YunoHost/apps
git clone -q git@github.com:YunoHost/apps.git "$script_dir/../../apps"	# Récupère la dernière version de https://github.com/YunoHost/apps

cd "$script_dir/../../apps"	# Se place dans le dossier du dépot git pour le script python

git checkout -b modify_level	# Créer une nouvelle branche pour commiter les changements

while read line
do
	if ! grep -q "_complete.log$" <<< "$line"	# Ignore les logs "complete", ne traite que les autres fichiers.
	then
		app=$(grep "^-> Test " < "$script_dir/../logs/$line")	# Récupère le nom du test, ajouté au début du log
		app=${app#-> Test }	# Supprime "-> Test " pour garder uniquement le nom du test
		if echo "$app" | grep -q " (Community)"; then
			list=Community	# Application communautaire
		elif echo "$app" | grep -q " (Official)"; then
			list=Official	# Application officielle
		fi
		app=${app%% ($list)*}
		app_level=$(tac "$script_dir/../logs/$line" | grep "Level of this application: " -m1)	# Tac affiche le fichier depuis la fin, et grep limite la recherche au premier terme trouvé pour ne prendre que le dernier résultat.
		if [ -n "$app_level" ]
		then	# Si le log contient un niveau pour l'app
			app_level="${app_level##*: }"
			app_level=$(echo "$app_level" | cut -d' ' -f1)
			./change_level.py ${list,,}.json "$app" "$app_level"	# Appel le script change_level.py pour modifier le niveau de l'app dans la liste. ${list,,} permet de passer la variable en minuscule
		fi
	fi
done <<< "$(ls -1 "$script_dir/../logs")"

git diff -U2 --raw | tee "$script_dir/mail_content"	# Affiche les changements (2 lignes de contexte suffisent à voir l'app)
git add --all *.json | tee -a "$script_dir/mail_content"	# Ajoute les modifications des listes au prochain commit
git commit -q -m "Update app's level" | tee -a "$script_dir/mail_content"

# Git doit être configuré sur la machine.
# git config --global user.email "MAIL..."
# git config --global user.name "yunohost-bot"
# ssh-keygen -t rsa -f $HOME/.ssh/github -P ''		Pour créer une clé ssh sans passphrase
# Host github.com
# IdentityFile ~/.ssh/github
# Dans le config ssh
# Et la clé doit être enregistrée dans le compte github de yunohost-bot
git push -q -u origin modify_level | tee -a "$script_dir/mail_content"

mail -s "[YunoHost] Modification du niveau des applications" "$dest" < "$script_dir/mail_content"	# Envoi le log de git par mail.
