#!/bin/bash

# Liste les apps YunoHost depuis les listes officials et community.

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

# JENKINS
jenkins_job_path="/var/lib/jenkins/jobs"
jenkins_url=$(sudo yunohost app map -a jenkins | cut -d':' -f1)

templist="$script_dir/templist"
dest=root	# Destinataire du mail. root par défaut pour envoyer à l'admin du serveur.

JENKINS_BUILD_JOB () {
	sed "s@__DEPOTGIT__@$app@g" "$script_dir/jenkins/jenkins_job.xml" > "$script_dir/jenkins/jenkins_job_load.xml"	# Renseigne le dépôt git dans le fichier de job de jenkins, et créer un nouveau fichier pour stocker les nouvelles informations
	sed -i "s@__PATH__@$(dirname "$script_dir")@g" "$script_dir/jenkins/jenkins_job_load.xml"	# Renseigne le chemin du script en prenant le dossier parent de ce script
	sed -i "s@__DAY__@$(( $RANDOM % 30 +1 ))@g" "$script_dir/jenkins/jenkins_job_load.xml"	# Détermine un jour de test aléatoire. Entre 1 et 30.

	sudo java -jar /var/lib/jenkins/jenkins-cli.jar -noCertificateCheck -s https://$jenkins_url/ -i "$script_dir/jenkins/jenkins_key" create-job "$appname" < "$script_dir/jenkins/jenkins_job_load.xml"	# Créer un job sur jenkins à partir du fichier xml
}

JENKINS_REMOVE_JOB () {
	sudo java -jar /var/lib/jenkins/jenkins-cli.jar -noCertificateCheck -s https://$jenkins_url/ -i "$script_dir/jenkins/jenkins_key" delete-job "$appname"	# Supprime le job dans jenkins
}
# / JENKINS


# Pour changer de logiciel de CI, ajouter simplement des fonctions pour l'ajout et la suppression de job et changer les appels qui suivent ainsi que le contenu de la variable job_path.
job_path=$jenkins_job_path	# Emplacement des fichiers de job, pour les archiver avant leur suppression

BUILD_JOB () {
	JENKINS_BUILD_JOB
}

REMOVE_JOB () {
	JENKINS_REMOVE_JOB
	APP_LOG=$(echo "${app#http*://}" | sed 's@/@_@g').log # Supprime http:// ou https:// au début et remplace les / par des _. Ceci sera le fichier de log de l'app.
	complete_log=$(basename -s .log "$APP_LOG")_complete.log	# Le complete log est le même que celui des résultats, auquel on ajoute _complete avant le .log
	sudo rm "$script_dir/../logs/$APP_LOG"
	sudo rm "$script_dir/../logs/$complete_log"
}

PARSE_LIST () {
	# Télécharge les listes d'applications Yunohost
	> "$templist"	# Vide la liste temporaire
	wget -nv https://raw.githubusercontent.com/YunoHost/apps/master/$1.json -O "$script_dir/$1.json"
	if [ "$1" = "official" ]; then
		grep_cmd="grep '\\\"url\\\":' \"$script_dir/$1.json\" | cut -d'\"' -f4"	# Liste les adresses des dépôts des applications officielles
	else
		grep_cmd="grep '\\\"state\\\": \\\"working\\\"' \"$script_dir/$1.json\" -A1 | grep '\\\"url\\\":' | cut -d'\"' -f4"	# Liste les adresses des dépôts des applications communautaires dites fonctionnelles.
	fi
	while read app
	do
		appname="$(basename --suffix=_ynh $app) \
($(echo ${1:0:1} | tr [:lower:] [:upper:])${1:1})"	# Isole le nom de l'application dans l'adresse github. Et la suffixe de (Community ou Official).
# Le `tr` sert seulement à passer le premier caractère en majuscule
		echo "$app;$appname" >> "$templist"	# Écrit la liste des apps avec un format plus lisible pour le script
	done <<< "$(eval $grep_cmd)"
}

ADD_JOB () {
	applist="$script_dir/$1_app"
	while read app
	do
		if ! grep -q "$app" "$applist"
		then	# Si l'app n'est pas dans la liste, c'est une nouvelle app.
			appname=$(echo "$app" | cut -d';' -f2)	# Prend le nom de l'app, après l'adresse du dépôt
			echo "Ajout de l'application $appname pour le dépôt $app" | tee -a "$script_dir/job_mail"
			echo "$app" >> "$applist"	# L'application est ajoutée à la liste, suivi du nom de l'app
			BUILD_JOB	# Renseigne le fichier du job et le charge dans le logiciel de CI
		fi
	done < "$templist"	# Liste la liste des applications officielles
}

CLEAR_JOB () {
	applist="$script_dir/$1_app"
	while read app
	do
		if ! grep -q "$app" "$templist"
		then	# Si l'app n'est pas dans la liste temporaire, elle doit être supprimée des jobs.
			appname=$(grep "$app" "$applist" | cut -d';' -f2)	# Prend le nom de l'app, après l'adresse du dépôt
			echo "Suppression de l'application $appname" | tee -a "$script_dir/job_mail"
			sed -i "/$appname/d" "$applist"	# Supprime l'application de la liste des jobs
			sudo tar -cpzf "$job_path/$appname $(date +%d-%m-%Y).tar.gz" -C "$job_path" "$appname"	# Créer une archive datée du job avant de le supprimer.
			REMOVE_JOB
		fi
	done < "$applist"	# Liste les apps dans la liste des jobs actuels
}

> "$script_dir/job_mail"    # Purge le contenu du mail

# Liste les applications officielles
PARSE_LIST official	# Extrait les adresses des apps et forme la liste des apps
CLEAR_JOB official	# Supprime les jobs pour les apps supprimées de la liste
ADD_JOB official	# Ajoute des job pour les nouvelles apps dans la liste

# Liste les applications communautaires
PARSE_LIST community	# Extrait les adresses des apps et forme la liste des apps
CLEAR_JOB community	# Supprime les jobs pour les apps supprimées de la liste
ADD_JOB community	# Ajoute des job pour les nouvelles apps dans la liste

if [ -s "$script_dir/job_mail" ]
then
    mail -s "Modification de la liste des applications" "$dest" < "$script_dir/job_mail"	# Envoi le rapport par mail.
fi
