#!/bin/bash

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

app=$1	# Le script prend en 1er argument le nom du test
app_log=$2	# Et en 2e, le log de l'app

ADD_LEVEL_IN_LIST () {
	list_name=$1
	list_file="$script_dir/$list_name"
	if [ -n "$app_level" ]
	then	# Si le log contient un niveau pour l'app
		if [ ! -e "$list_file" ]; then
			touch "$list_file"	# Créer la liste si le fichier n'existe pas.
		fi
		if grep -q "$app" "$list_file"; then
			sed -i "s/$app:.*/$app:$app_level/" "$list_file"	# Remplace le niveau de l'app dans la liste
		else	# Ou si l'app n'est pas déjà dans le fichier
			echo "$app:$app_level" >> "$list_file"	# Inscrit le level de l'app dans la liste
		fi
	fi
}

if [ ! -e "$script_dir/list_level_stable" ]
then	# Si le fichier list_level_stable n'existe pas, c'est la première exécution
	while read line	# Le fichier list_level_stable est constitué une première fois à partir des logs existants
	do
		if ! grep -q "_complete.log$" <<< "$line"	# Ignore les logs "complete", ne traite que les autres fichiers.
		then
			app=$(grep "^-> Test " < "$script_dir/../logs/$line")	# Récupère le nom du test, ajouté au début du log
			app=${app#-> Test }	# Supprime "-> Test " pour garder uniquement le nom du test
			app_level=$(tac "$script_dir/../logs/$line" | grep "Niveau de l'application: " -m1)	# Tac affiche le fichier depuis la fin, et grep limite la recherche au premier terme trouvé pour ne prendre que le dernier résultat.
			if [ -n "$app_level" ]
			then	# Si le log contient un niveau pour l'app
				app_level="$(echo $(expr match "$app_level" '.*\(.[0-9]*\)'))"	# Extrait uniquement la valeur numérique du résultat avec match.
				echo "$app:$app_level" >> "$script_dir/list_level_stable"	# Inscrit le level de l'app dans le fichier list_level_stable
			fi
		fi
	done <<< "$(ls -1 "$script_dir/../logs")"
else
	# Récupère le niveau de l'application
	app_level=$(tac "$script_dir/../logs/$app_log" | grep "Niveau de l'application: " -m1)	# Tac affiche le fichier depuis la fin, et grep limite la recherche au premier terme trouvé pour ne prendre que le dernier résultat.
	if [ -n "$app_level" ]
	then	# Si le log contient un niveau pour l'app
		app_level="$(echo $(expr match "$app_level" '.*\(.[0-9]*\)'))"	# Extrait uniquement la valeur numérique du résultat avec match.
	fi
	# Traite l'information selon le type de test
	if echo "$app" | grep -q "(testing)\|(unstable)"	# Vérifie si c'est un test testing ou unstable
	then	# Si c'est un test sur testing ou unstable, compare avec stable
		if echo "$app" | grep -q "(testing)"; then
			type=testing
		else
			type=unstable
		fi
		ADD_LEVEL_IN_LIST list_level
		if [ -s "$script_dir/../work_list" ]; then	# Si la file d'attente n'est pas vide
			exit 0	# Le script a terminé son travail
		else	# Si la file d'attente est vide, la série de test est terminée.
			> "$script_dir/mail_diff_level"
			while read line	# Compare chaque niveau avec le niveau en stable
			do
				app=$(echo ${line%:*})	# Supprime après les : pour garder le nom de l'app
				app=$(echo ${app% \($type\)})	# Et supprime le type, testing ou unstable
				app_level=$(echo ${line##*:})	# Et avant les : pour garder le niveau seulement
				stable_level=$(grep "$app" "$script_dir/list_level_stable" | cut -d: -f2)	# Récupère le niveau de l'app dans la liste stable
				if [ "$app_level" -ne "$stable_level" ]	# Si le niveau est différent
				then
					echo "- Changement de niveau de l'app $app de $stable_level en stable vers $app_level en $type." >> "$script_dir/mail_diff_level"
				fi
			done < "$script_dir/list_level"
		fi
	else	# Si c'est un test sur stable, modifie les niveaux de référence
		ADD_LEVEL_IN_LIST list_level_stable
	fi
fi

if [ -s "$script_dir/mail_diff_level" ]; then	# Si le mail n'est pas vide
# 	mail -s "Différences de niveaux entre stable et $type" "$dest" < "$script_dir/mail_diff_level"	# Envoi le différentiel de niveau par mail
	if [ $(wc -l "$script_dir/mail_diff_level" | cut -d' ' -f1) -gt 1 ]
	then	# En cas de message sur plusieurs lignes, je sais pas comment faire...
		paste=$(cat "$script_dir/mail_diff_level" | yunopaste)
		echo "Différences de niveaux entre stable et $type: $paste" > "$script_dir/mail_diff_level"
	fi
	"$script_dir/xmpp_bot_diff/xmpp_post.sh" "$(cat "$script_dir/mail_diff_level")"	# Notifie sur le salon apps
	rm "$script_dir/list_level"
fi
