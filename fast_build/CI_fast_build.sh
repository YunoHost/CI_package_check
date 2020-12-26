#!/bin/bash

# Met en place Yunohost avec Jenkins sur un serveur dédié

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

LOG_BUILD_AUTO_CI="$script_dir/Log_build_fast_ci.log"
CI_USER=ynhci

DOMAIN=$1
YUNO_PWD=$2

# JENKINS
SETUP_JENKINS () {
	CI_PATH=jenkins

	echo -e "\e[1m> Installation de jenkins...\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
	sudo yunohost app install https://github.com/YunoHost-Apps/jenkins_ynh -a "domain=$DOMAIN&path=/$CI_PATH&is_public=Yes" | tee -a "$LOG_BUILD_AUTO_CI"

	# Réduit le nombre de tests simultanés à 1 sur jenkins
	sudo sed -i "s/<numExecutors>.*</<numExecutors>1</" /var/lib/jenkins/config.xml

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
	sudo yunohost tools postinstall --domain $DOMAIN --password $YUNO_PWD
fi

if [ -z "$DOMAIN" ]; then
	DOMAIN=$(sudo yunohost domain list -l 1 | cut -d' ' -f2)	# Récupère le premier domaine diponible dans Yunohost
fi

echo "127.0.0.1 $DOMAIN	#CI_APP" | sudo tee -a /etc/hosts	# Renseigne le domain dans le host

if ! sudo yunohost user list --output-as json | grep -q "\"username\": \"$CI_USER\""	# Vérifie si l'utilisateur existe
then
	echo -e "\e[1m> Création d'un utilisateur YunoHost\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
	sudo yunohost user create --firstname "$CI_USER" --mail "$CI_USER@$DOMAIN" --lastname "$CI_USER" "$CI_USER" --password $YUNO_PWD
fi

# Installation du logiciel de CI qui servira d'interface
SETUP_CI_APP

echo -e "\e[1mMise en place de Package check à l'aide des scripts d'intégration continue\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
"$script_dir/../build_CI.sh"

# Modifie la config nginx pour ajouter l'accès aux logs
echo | sudo tee -a "/etc/nginx/conf.d/$DOMAIN.d/$CI_PATH.conf" <<EOF | tee -a "$LOG_BUILD_AUTO_CI"
location /$CI_PATH/logs {
   alias $(dirname "$script_dir")/logs/;
   autoindex on;
}
EOF

echo -e "\e[1mVérification des droits d'accès\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
if sudo su -l $CI -c "ls \"$script_dir\"" > /dev/null 2<&1
then
	echo -e "\e[92mLes droits d'accès sont suffisant.\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
else
	echo -e "\e[91m$CI n'a pas les droits suffisants pour accéder aux scripts !\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
fi

cp "$script_dir/config.modele" "$script_dir/config"	# Créer le fichier de config

echo ""
echo -e "\e[92mLe fichier config doit être modifié pour renseigner le token et le server_id.\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
echo -e "\e[92mCela permettra au serveur de s'arrêter de lui-même en cas d'inactivité.\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
