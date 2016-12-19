#!/bin/bash

# Liste les apps YunoHost depuis les listes officials et community.

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

# Télécharge les listes d'applications Yunohost
wget -nv https://raw.githubusercontent.com/YunoHost/apps/master/official.json -O "$script_dir/official.json"
wget -nv https://raw.githubusercontent.com/YunoHost/apps/master/community.json -O "$script_dir/community.json"

# JENKINS
jenkins_job_path="/var/lib/jenkins/jobs"
jenkins_url=$(sudo yunohost app map -a jenkins | cut -d':' -f1)

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
}


ADD_JOB () {
	applist="$script_dir/$1_app"
	echo "$app;$appname" >> "$templist"	# Ajoute l'app lue à la liste des apps traitée par le script
	if ! grep -q "$app" "$applist"
	then	# Si l'app n'est pas dans la liste, c'est une nouvelle app.
		echo "Ajout de l'application $appname"
		echo "$app;$appname" >> "$applist"	# L'application est ajoutée à la liste, suivi du nom de l'app
		BUILD_JOB	# Renseigne le fichier du job et le charge dans le logiciel de CI
	fi
}

CLEAR_JOB () {
	applist="$script_dir/$1_app"
	while read app
	do
		if ! grep -q "$app" "$templist"
		then	# Si l'app n'est pas dans la liste temporaire, elle doit être supprimée des jobs.
			appname=$(grep "$app" "$applist" | cut -d';' -f2)	# Prend le nom de l'app, après l'adresse du dépôt
			echo "Suppression de l'application $appname"
			sed -i "/$appname/d" "$applist"	# Supprime l'application de la liste des jobs
			sudo tar -cpzf "$job_path/$appname $(date +%d-%m-%Y).tar.gz" -C "$job_path" "$appname"	# Créer une archive datée du job avant de le supprimer.
			REMOVE_JOB
		fi
	done <<< "$(cat "$applist")"	# Liste les apps dans la liste des jobs actuels
}

templist="$script_dir/templist"

# Liste les applications officielles
> "$templist"	# Vide la liste temporaire
while read app
do
	appname="$(basename --suffix=_ynh $app) (Official)"	# Isole le nom de l'application dans l'adresse github
	ADD_JOB official	# Ajoute un job si l'app est nouvelle dans la liste
done <<< "$(grep "\"url\":" "$script_dir/official.json" | cut -d'"' -f4)"	# Liste les adresses des dépôts des applications officielles
CLEAR_JOB official	# Supprime les jobs pour les apps supprimées de la liste

# Liste les applications communautaires
> "$templist"	# Vide la liste temporaire
while read app
do
	appname="$(basename --suffix=_ynh $app) (Community)"	# Isole le nom de l'application dans l'adresse github
	ADD_JOB community	# Ajoute un job si l'app est nouvelle dans la liste
done <<< "$(grep "\"state\": \"working\"" "$script_dir/community.json" -A1 \
| grep "\"url\":" | cut -d'"' -f4)"	# Liste les appplications communautaires dites fonctionnelles.
# Et isole les adresses des dépôts
CLEAR_JOB community	# Supprime les jobs pour les apps supprimées de la liste
