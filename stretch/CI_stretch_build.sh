#!/bin/bash

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

echo -e "\e[1m> Installation des dépendances de jenkins...\e[0m"
apt-get update
apt-get install default-jre-headless daemon psmisc net-tools git ifupdown sudo

mkdir -p /etc/network/interfaces.d

echo -e "\e[1m> Installation de jenkins...\e[0m"
version="2.60.3"
wget --no-verbose https://pkg.jenkins.io/debian-stable/binary/jenkins_${version}_all.deb
dpkg --install jenkins_${version}_all.deb
rm jenkins_${version}_all.deb

echo -e "\e[1m> Configure jenkins...\e[0m"
# Ignore le Setup Wizard
sed -i "s@-Djava.awt.headless=true@& -Djenkins.install.runSetupWizard=false@g" /etc/default/jenkins

# Mise en place de la connexion ssh pour jenkins cli.
# Création de la clé ssh
echo -e "\e[1m> Créer la clé ssh pour jenkins-cli.\e[0m" 
ssh-keygen -t rsa -b 4096 -N "" -f "$script_dir/jenkins_key" > /dev/null 
chown root: "$script_dir/jenkins_key" 
chmod 600 "$script_dir/jenkins_key" 

CI_USER=ynh_ci

# Configuration de la clé pour l'user dans jenkins
echo -e "\e[1m> Créer la base de la configuration de l'utilisateur jenkins.\e[0m" 
mkdir -p "/var/lib/jenkins/users/$CI_USER"      # Créer le dossier de l'utilisateur
cp "$script_dir/jenkins/user_config.xml" "/var/lib/jenkins/users/$CI_USER/config.xml"   # Copie la config de base.
sed -i "s/__USER__/$CI_USER/g" "/var/lib/jenkins/users/$CI_USER/config.xml"     # Ajoute le nom de l'utilisateur
sed -i "s|__SSH_KEY__|$(cat "$script_dir/jenkins_key.pub")|"  "/var/lib/jenkins/users/$CI_USER/config.xml"      # Ajoute la clé publique
chown jenkins: -R "/var/lib/jenkins/users"

echo -e "\e[1m> Restart jenkins...\e[0m"
sleep 1
systemctl restart jenkins

tempfile="$(mktemp)"
tail -f -n1 /var/log/jenkins/jenkins.log > "$tempfile" &	# Suit le démarrage dans le log
PID_TAIL=$!	# Récupère le PID de la commande tail, qui est passée en arrière plan.

echo -e "\e[1m> Surveille le démarrage de jenkins...\e[0m"
jenkins_cli="java -jar /var/lib/jenkins/jenkins-cli.jar -remoting -s http://localhost:8080"

while true
do	# La boucle attend le démarrage de jenkins
	if grep -q "Jenkins is fully up and running" "$tempfile"; then
		wget -nv --no-check-certificate http://localhost:8080/jnlpJars/jenkins-cli.jar -O /var/lib/jenkins/jenkins-cli.jar
		echo ""
		while true
		do	# La boucle attend la mise à jour des dépôts de plugins.
			if test -e /var/lib/jenkins/updates/default.json; then
				break;
			else
				echo -n "."
				sleep 1
			fi
		done
		break;
	fi
	sleep 1
	echo -n "."
done
kill -s 15 $PID_TAIL	# Arrête l'exécution de tail.
rm "$tempfile"

echo -e "\e[1m> Installe les plugins...\e[0m"
# Installation des plugins recommandés (Lors de l'install avec le Setup Wizard)
$jenkins_cli install-plugin cloudbees-folder	# Folders Plugin
$jenkins_cli install-plugin antisamy-markup-formatter	# OWASP Markup Formatter Plugin
$jenkins_cli install-plugin pam-auth	# PAM Authentication plugin
$jenkins_cli install-plugin mailer	# Mailer Plugin
$jenkins_cli install-plugin ldap	# LDAP Plugin
$jenkins_cli install-plugin matrix-auth	# Matrix Authorization Strategy Plugin
$jenkins_cli install-plugin build-timeout	# Build timeout plugin
$jenkins_cli install-plugin credentials-binding	# Credentials Binding Plugin
$jenkins_cli install-plugin timestamper	# Timestamper
$jenkins_cli install-plugin ws-cleanup	# Workspace Cleanup Plugin
$jenkins_cli install-plugin ant	# Ant Plugin
$jenkins_cli install-plugin gradle	# Gradle Plugin
$jenkins_cli install-plugin workflow-aggregator	# Pipeline
$jenkins_cli install-plugin pipeline-stage-view	# Pipeline: Stage View Plugin
$jenkins_cli install-plugin git	# Git plugin
$jenkins_cli install-plugin github-organization-folder	# GitHub Organization Folder Plugin
$jenkins_cli install-plugin subversion	# Subversion Plug-in
$jenkins_cli install-plugin email-ext	# Email Extension Plugin
$jenkins_cli install-plugin ssh-slaves	# SSH Slaves plugin

# Installation de plugins supplémentaires pour le confort
$jenkins_cli install-plugin ansicolor	# Prise en charge des couleurs pour la sortie console. Améliore la lisibilité de la console (par contre les couleurs ne passent pas...)
$jenkins_cli install-plugin fstrigger # Monitoring sur le système de fichier local. Pour surveiller des dossiers de code et builder sur les changements.

echo -e "\e[1m> Restart jenkins...\e[0m"
systemctl restart jenkins

# Réduit le nombre de tests simultanés à 1 sur jenkins
sed -i "s/<numExecutors>.*</<numExecutors>1</" /var/lib/jenkins/config.xml



echo -e "\e[1mMise en place de Package check à l'aide des scripts d'intégration continue\e[0m"
"$script_dir/build_CI.sh"



echo -e "\e[1mVérification des droits d'accès\e[0m"
if su -l $CI -c "ls \"$script_dir\"" > /dev/null 2<&1
then
	echo -e "\e[92mLes droits d'accès sont suffisant.\e[0m"
else
	echo -e "\e[91m$CI n'a pas les droits suffisants pour accéder aux scripts !\e[0m"
fi
