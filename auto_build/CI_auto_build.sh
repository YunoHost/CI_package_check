#!/bin/bash

# Met en place Yunohost avec Jenkins. Puis créer des jobs pour chaque app de Yunohost.
# Le hook de github sur chaque app doit toutefois être mis en place manuellement.

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

LOG_BUILD_AUTO_CI="$script_dir/Log_build_auto_ci.log"
CI_USER=ynhci

# JENKINS
SETUP_JENKINS () {
	CI=jenkins	# Utilisateur avec lequel s'exécute jenkins

	echo -e "\e[1m> Installation de jenkins...\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
	sudo yunohost app install https://github.com/YunoHost-Apps/jenkins_ynh -a "domain=$DOMAIN&path=/jenkins&is_public=Yes" | tee -a "$LOG_BUILD_AUTO_CI"

	# Réduit le nombre de tests simultanés à 1 sur jenkins
	sudo sed -i "s/<numExecutors>.*</<numExecutors>1</" /var/lib/jenkins/config.xml

	# Mise en place de la connexion ssh pour jenkins cli.
	# Création de la clé ssh
	echo -e "\e[1m> Créer la clé ssh pour jenkins-cli.\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
	ssh-keygen -t rsa -b 4096 -N "" -f "$script_dir/jenkins/jenkins_key" > /dev/null | tee -a "$LOG_BUILD_AUTO_CI"
	sudo chown root: "$script_dir/jenkins/jenkins_key" | tee -a "$LOG_BUILD_AUTO_CI"
	sudo chmod 600 "$script_dir/jenkins/jenkins_key" | tee -a "$LOG_BUILD_AUTO_CI"

	# Configuration de la clé pour l'user dans jenkins
	echo -e "\e[1m> Créer la base de la configuration de l'utilisateur jenkins.\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
	sudo mkdir -p "/var/lib/jenkins/users/$CI_USER"	# Créer le dossier de l'utilisateur
	sudo cp "$script_dir/jenkins/user_config.xml" "/var/lib/jenkins/users/$CI_USER/config.xml"	# Copie la config de base.
	sudo sed -i "s/__USER__/$CI_USER/g" "/var/lib/jenkins/users/$CI_USER/config.xml" | tee -a "$LOG_BUILD_AUTO_CI"	# Ajoute le nom de l'utilisateur
	sudo sed -i "s|__SSH_KEY__|$(cat "$script_dir/jenkins/jenkins_key.pub")|"  "/var/lib/jenkins/users/$CI_USER/config.xml" | tee -a "$LOG_BUILD_AUTO_CI"	# Ajoute la clé publique
	sudo chown jenkins: -R "/var/lib/jenkins/users"

	# Configure le port ssh sur jenkins
	echo | sudo tee "/var/lib/jenkins/org.jenkinsci.main.modules.sshd.SSHD.xml" <<EOF | tee -a "$LOG_BUILD_AUTO_CI"
<?xml version='1.0' encoding='UTF-8'?>
<org.jenkinsci.main.modules.sshd.SSHD>
  <port>0</port>
</org.jenkinsci.main.modules.sshd.SSHD>
EOF
	sudo chown jenkins: "/var/lib/jenkins/org.jenkinsci.main.modules.sshd.SSHD.xml" | tee -a "$LOG_BUILD_AUTO_CI"

	echo -e "\e[1m> Redémarre jenkins pour prendre en compte la clé ssh...\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
	sudo service jenkins restart | tee -a "$LOG_BUILD_AUTO_CI"

	tempfile="$(mktemp)"
	tail -f -n1 /var/log/jenkins/jenkins.log > "$tempfile" &	# Suit le démarrage dans le log
	PID_TAIL=$!	# Récupère le PID de la commande tail, qui est passée en arrière plan.
	timeout=3600
	for i in `seq 1 $timeout`
	do	# La boucle attend le démarrage de jenkins Ou $timeout (Le démarrage sur arm est trèèèèèèèèès long...).
		if grep -q "Jenkins is fully up and running" "$tempfile"; then
			echo "Jenkins a démarré correctement." | tee -a "$LOG_BUILD_AUTO_CI"
			break
		fi
		sleep 5
	done
	kill -s 15 $PID_TAIL > /dev/null	# Arrête l'exécution de tail.
	sudo rm "$tempfile"
	if [ "$i" -ge $timeout ]; then
		echo "Jenkins n'a pas démarré dans le temps imparti." | tee -a "$LOG_BUILD_AUTO_CI"
	fi

	# Créer les filtres de vues
	echo -e "\e[1m> Création des vues dans jenkins\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
	sudo java -jar /var/lib/jenkins/jenkins-cli.jar -noCertificateCheck -s https://$DOMAIN/jenkins/ -i "$script_dir/jenkins/jenkins_key" create-view Official < "$script_dir/jenkins/Views_official.xml"
	sudo java -jar /var/lib/jenkins/jenkins-cli.jar -noCertificateCheck -s https://$DOMAIN/jenkins/ -i "$script_dir/jenkins/jenkins_key" create-view Community < "$script_dir/jenkins/Views_community.xml"

	# Passe l'application à la racine du domaine
	sudo yunohost app makedefault -d "$DOMAIN" jenkins
}
# / JENKINS

SETUP_CI_APP () {
	# Installation du logiciel de CI qui servira d'interface
	# Pour changer de logiciel, ajouter simplement une fonction et changer l'appel qui suit.
	SETUP_JENKINS
}

echo -e "\e[1m> Vérifie que YunoHost est déjà installé.\e[0m" | tee "$LOG_BUILD_AUTO_CI"
if [ ! -e /usr/bin/yunohost ]
then
	echo -e "\e[1m> YunoHost n'est pas installé.\e[0m" | tee "$LOG_BUILD_AUTO_CI"
	echo -e "\e[1mInstallation de YunoHost...\e[0m" | tee "$LOG_BUILD_AUTO_CI"
	sudo apt-get update | tee "$LOG_BUILD_AUTO_CI" 2>&1
	sudo apt-get install -y sudo git | tee "$LOG_BUILD_AUTO_CI" 2>&1
	git clone https://github.com/YunoHost/install_script /tmp/install_script
	cd /tmp/install_script; sudo ./install_yunohost -a | tee "$LOG_BUILD_AUTO_CI" 2>&1

	echo -e "\e[1m> Post install Yunohost\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
	sudo yunohost tools postinstall
fi

DOMAIN=$(sudo yunohost domain list -l 1 | cut -d' ' -f2)	# Récupère le premier domaine diponible dans Yunohost

echo "127.0.0.1 $DOMAIN #CI_APP" | sudo tee -a /etc/hosts	# Renseigne le domain dans le host

if ! sudo yunohost user list --output-as json | grep -q "\"username\": \"$CI_USER\""	# Vérifie si l'utilisateur existe
then
	echo -e "\e[1m> Création d'un utilisateur YunoHost\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
	sudo yunohost user create --firstname "$CI_USER" --mail "$CI_USER@$DOMAIN" --lastname "$CI_USER" "$CI_USER"
fi

# Installation du logiciel de CI qui servira d'interface
SETUP_CI_APP

echo -e "\e[1mMise en place de Package check à l'aide des scripts d'intégration continue\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
"$script_dir/../build_CI.sh" #| tee -a "$LOG_BUILD_AUTO_CI" 2>&1

touch "$script_dir/community_app"
touch "$script_dir/official_app"

# Liste les apps Yunohost et créer les jobs à l'aide du script list_app_ynh.sh
echo -e "\e[1mCréation des jobs\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
sudo "$script_dir/list_app_ynh.sh"

# Met en place le cron pour maintenir à jour la liste des jobs.
echo -e "\e[1mAjout de la tâche cron\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
cat "$script_dir/CI_package_check_cron" | sudo tee -a "/etc/cron.d/CI_package_check" > /dev/null	# Ajoute le cron à la suite du cron de CI déjà en place.
sudo sed -i "s@__PATH__@$script_dir@g" "/etc/cron.d/CI_package_check"	# Renseigne l'emplacement du script dans le cron

echo -e "\e[1mVérification des droits d'accès\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
if sudo su -l $CI -c "ls \"$script_dir\"" > /dev/null 2<&1
then
	echo -e "\e[92mLes droits d'accès sont suffisant.\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
else
	echo -e "\e[91m$CI n'a pas les droits suffisants pour accéder aux scripts !\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
fi
