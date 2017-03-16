#!/bin/bash

# Met en place Yunohost avec Jenkins. Puis créer des jobs pour chaque app de Yunohost.
# Le hook de github sur chaque app doit toutefois être mis en place manuellement.

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

LOG_BUILD_AUTO_CI="$script_dir/Log_build_auto_ci.log"
CI_USER=ynhci

DOMAIN=$1
YUNO_PWD=$2

# JENKINS
SETUP_JENKINS () {
	CI=jenkins	# Utilisateur avec lequel s'exécute jenkins
	CI_PATH=jenkins

	echo -e "\e[1m> Installation de jenkins...\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
	sudo yunohost app install https://github.com/YunoHost-Apps/jenkins_ynh -a "domain=$DOMAIN&path=/$CI_PATH&is_public=Yes" | tee -a "$LOG_BUILD_AUTO_CI"

	# Réduit le nombre de tests simultanés à 1 sur jenkins
	sudo sed -i "s/<numExecutors>.*</<numExecutors>1</" /var/lib/jenkins/config.xml
	# Vue "Stable" par défaut au lieu de "All"
	sudo sed -i "s/<primaryView>.*</<primaryView>Stable</" /var/lib/jenkins/config.xml

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
	sudo java -jar /var/lib/jenkins/jenkins-cli.jar -noCertificateCheck -s https://$DOMAIN/jenkins/ -i "$script_dir/jenkins/jenkins_key" create-view Stable < "$script_dir/jenkins/Views_stable.xml"
	sudo java -jar /var/lib/jenkins/jenkins-cli.jar -noCertificateCheck -s https://$DOMAIN/jenkins/ -i "$script_dir/jenkins/jenkins_key" create-view Testing < "$script_dir/jenkins/Views_testing.xml"
	sudo java -jar /var/lib/jenkins/jenkins-cli.jar -noCertificateCheck -s https://$DOMAIN/jenkins/ -i "$script_dir/jenkins/jenkins_key" create-view Unstable < "$script_dir/jenkins/Views_unstable.xml"

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
	if [ -n "$DOMAIN" ]; then
		domain_arg="--domain $DOMAIN"
	else
		domain_arg=""
	fi
        if [ -n "$YUNO_PWD" ]; then
                pass_arg="--password $YUNO_PWD"
        else
                pass_arg=""
        fi
	sudo yunohost tools postinstall $domain_arg $pass_arg
fi

if [ -z "$DOMAIN" ]; then
	DOMAIN=$(sudo yunohost domain list -l 1 | cut -d' ' -f2)	# Récupère le premier domaine diponible dans Yunohost
fi

echo "127.0.0.1 $DOMAIN	#CI_APP" | sudo tee -a /etc/hosts	# Renseigne le domain dans le host

if [ -n "$YUNO_PWD" ]; then
        pass_arg="--admin-password $YUNO_PWD"
else
        pass_arg=""
fi

if ! sudo yunohost user list --output-as json $pass_arg | grep -q "\"username\": \"$CI_USER\""	# Vérifie si l'utilisateur existe
then
	if [ -n "$YUNO_PWD" ]; then
		pass_arg="--password $YUNO_PWD --admin-password $YUNO_PWD"
	else
		pass_arg=""
	fi
	echo -e "\e[1m> Création d'un utilisateur YunoHost\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
	sudo yunohost user create --firstname "$CI_USER" --mail "$CI_USER@$DOMAIN" --lastname "$CI_USER" "$CI_USER" $pass_arg
fi

# Installation du logiciel de CI qui servira d'interface
SETUP_CI_APP

echo -e "\e[1mMise en place de Package check à l'aide des scripts d'intégration continue\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
"$script_dir/../build_CI.sh" #| tee -a "$LOG_BUILD_AUTO_CI" 2>&1

# Met en place les locks pour éviter des démarrages intempestifs durant le build
touch "$script_dir/../CI.lock"
touch "$script_dir/../package_check/pcheck.lock"

# Déplace le snapshot et le remplace par un lien symbolique
echo -e "\e[1mRemplacement du snapshot par un lien symbolique\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
LXC_NAME=$(cat "$script_dir/../package_check/config" | grep LXC_NAME= | cut -d '=' -f2)
sudo mv /var/lib/lxcsnaps/$LXC_NAME /var/lib/lxcsnaps/pcheck_stable
sudo ln -s /var/lib/lxcsnaps/pcheck_stable /var/lib/lxcsnaps/$LXC_NAME

# Modifie la tâche cron pour utiliser auto_upgrade_container
echo -e "\e[1mModification de la tâche cron pour l'upgrade\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
sudo sed -i "s@package_check/sub_scripts/auto_upgrade.sh.*@auto_build/auto_upgrade_container.sh stable\"@g" "/etc/cron.d/CI_package_check" | tee -a "$LOG_BUILD_AUTO_CI"

 ### Solution en multiples conteneur abandonnée en raison d'une erreur récurente "curl: (7) Failed to connect to sous.domain.tld port 80: No route to host"
# echo -e "\e[1mClone le conteneur LXC pour la version testing\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
# LXC_NAME=$(cat "$script_dir/../package_check/sub_scripts/lxc_build.sh" | grep LXC_NAME= | cut -d '=' -f2)
# sudo lxc-copy --name=$LXC_NAME --newname=pcheck_testing | tee -a "$LOG_BUILD_AUTO_CI"

# Met en place le cron pour maintenir à jour la liste des jobs. Et le cron pour changer le niveau des apps
echo -e "\e[1mAjout de la tâche cron\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
cat "$script_dir/CI_package_check_cron" | sudo tee -a "/etc/cron.d/CI_package_check" > /dev/null	# Ajoute le cron à la suite du cron de CI déjà en place.
sudo sed -i "s@__PATH__@$script_dir@g" "/etc/cron.d/CI_package_check"	# Renseigne l'emplacement du script dans le cron

# Modifie la config nginx pour ajouter l'accès aux logs
echo | sudo tee -a "/etc/nginx/conf.d/$DOMAIN.d/$CI_PATH.conf" <<EOF | tee -a "$LOG_BUILD_AUTO_CI"
location /$CI_PATH/logs {
   alias $(dirname "$script_dir")/logs/;
   autoindex on;
}
EOF

# Créer le fichier de configuration
echo | sudo tee "$script_dir/auto.conf" <<EOF | tee -a "$LOG_BUILD_AUTO_CI"
# Mail pour le rapport hebdommadaire
MAIL_DEST=root


# Instance disponibles sur d'autres architectures. Un job supplémentaire sera créé pour chaque architecture indiquée.
x86-64b=0
x86-32b=0
ARM=0

# Les informations qui suivent ne doivent pas être modifiées. Elles sont générées par le script d'installation.
# Utilisateur avec lequel s'exécute le logiciel de CI
CI=$CI

# Path du logiciel de CI
CI_PATH=$CI_PATH

# Domaine utilisé
DOMAIN=$DOMAIN
}
EOF
echo -e "\e[1mLe fichier de configuration a été créée dans $script_dir/auto.conf\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"

echo -e "\e[1mMise en place du bot XMPP\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
sudo apt-get install python-xmpp | tee -a "$LOG_BUILD_AUTO_CI"
git clone https://github.com/YunoHost/weblate2xmpp "$script_dir/xmpp_bot" | tee -a "$LOG_BUILD_AUTO_CI"
sudo touch "$script_dir/xmpp_bot/password" | tee -a "$LOG_BUILD_AUTO_CI"
sudo chmod 600 "$script_dir/xmpp_bot/password" | tee -a "$LOG_BUILD_AUTO_CI"
echo "python \"$script_dir/xmpp_bot/to_room.py\" \$(sudo cat \"$script_dir/xmpp_bot/password\") \"\$@\" apps" \
> "$script_dir/xmpp_bot/xmpp_post.sh" | tee -a "$LOG_BUILD_AUTO_CI"
sudo chmod +x "$script_dir/xmpp_bot/xmpp_post.sh" | tee -a "$LOG_BUILD_AUTO_CI"

## ---
# Création des autres instances

 ### Solution en multiples conteneur abandonnée...
# PLAGE_IP=$(cat "$script_dir/../package_check/sub_scripts/lxc_build.sh" | grep PLAGE_IP= | cut -d '"' -f2)
# LXC_BRIDGE=$(cat "$script_dir/../package_check/sub_scripts/lxc_build.sh" | grep LXC_BRIDGE= | cut -d '=' -f2)

for change_version in testing unstable
do
 ### Solution en multiples conteneur abandonnée...
# 	change_LXC_NAME=pcheck_$change_version
# 	change_LXC_BRIDGE=pcheck-$change_version
# 	if [ $change_version == testing ]
# 	then
# 		change_PLAGE_IP="10.1.5"
# 		echo -e "\e[1mClone le conteneur testing pour la version unstable\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
# 		sudo lxc-copy --name=pcheck_testing --newname=pcheck_unstable >> "$LOG_BUILD_AUTO_CI" 2>&1
# 	else
# 		change_PLAGE_IP="10.1.6"
# 	fi

 ### Solution en multiples conteneur abandonnée...
# 	echo -e "\e[1m> Modification de l'ip de la version $change_version\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
# 	sudo sed -i "s@$PLAGE_IP@$change_PLAGE_IP@" /var/lib/lxc/$change_LXC_NAME/rootfs/etc/network/interfaces >> "$LOG_BUILD_AUTO_CI" 2>&1
# 	echo -e "\e[1m> Le nom du veth\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
# 	sudo sed -i "s@^lxc.network.veth.pair = ${LXC_NAME}@lxc.network.veth.pair = $change_LXC_NAME@" /var/lib/lxc/$change_LXC_NAME/config >> "$LOG_BUILD_AUTO_CI" 2>&1
# 	echo -e "\e[1m> Et le nom du bridge\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
# 	sudo sed -i "s@^lxc.network.link = ${LXC_BRIDGE}@lxc.network.link = $change_LXC_BRIDGE@" /var/lib/lxc/$change_LXC_NAME/config >> "$LOG_BUILD_AUTO_CI" 2>&1
# 	echo -e "\e[1m> Et enfin renseigne /etc/hosts sur $change_version\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
# 	sudo sed -i "s@^127.0.0.1 ${LXC_NAME}@127.0.0.1 $change_LXC_NAME@" /var/lib/lxc/$change_LXC_NAME/rootfs/etc/hosts >> "$LOG_BUILD_AUTO_CI" 2>&1

	# Créer le dossier pour le snapshot
	sudo mkdir /var/lib/lxcsnaps/pcheck_$change_version
	echo -e "\e[1m> Duplique le snapshot stable vers $change_version\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
	sudo cp -a /var/lib/lxcsnaps/pcheck_stable/snap0 /var/lib/lxcsnaps/pcheck_$change_version/snap0

	echo -e "\e[1m> Configure les dépôts du conteneur sur $change_version\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
	if [ $change_version == testing ]; then
		source="testing"
	else
		source="testing unstable"
	fi
	sudo echo "deb http://repo.yunohost.org/debian/ jessie stable $source" | sudo tee  /var/lib/lxcsnaps/pcheck_$change_version/snap0/rootfs/etc/apt/sources.list.d/yunohost.list >> "$LOG_BUILD_AUTO_CI" 2>&1

	# Supprime les locks pour autoriser l'upgrade
	sudo rm -f "$script_dir/../package_check/pcheck.lock" "$script_dir/../CI.lock"

	echo -e "\e[1m> Effectue la mise à jour du conteneur sur $change_version\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
	sudo "$script_dir/auto_upgrade_container.sh" $change_version | tee -a "$LOG_BUILD_AUTO_CI"

	# Remet les locks après l'upgrade
	touch "$script_dir/../CI.lock" "$script_dir/../package_check/pcheck.lock"

 ### Solution en multiples conteneur abandonnée...
# 	echo -e "\e[1m> Créer une copie des scripts CI_package_check pour $change_version\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
# 	parent_dir="$(echo "$(dirname "$(dirname "$script_dir")")")"
# 	new_CI_dir="$parent_dir/CI_package_check_$change_version"
# 	sudo cp -a "$parent_dir/CI_package_check" "$new_CI_dir"
# 	echo -e "\e[1m> Modifie les infos du conteneur dans le script build\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
 ### Solution en multiples conteneur abandonnée...
# 	sudo sed -i "s@^PLAGE_IP=.*@PLAGE_IP=\"$change_PLAGE_IP\"@" "$new_CI_dir/package_check/sub_scripts/lxc_build.sh" >> "$LOG_BUILD_AUTO_CI" 2>&1
# 	sudo sed -i "s@^LXC_NAME=.*@LXC_NAME=$change_LXC_NAME@" "$new_CI_dir/package_check/sub_scripts/lxc_build.sh" >> "$LOG_BUILD_AUTO_CI" 2>&1
# 	sudo sed -i "s@^LXC_BRIDGE=.*@LXC_BRIDGE=$change_LXC_BRIDGE@" "$new_CI_dir/package_check/sub_scripts/lxc_build.sh" >> "$LOG_BUILD_AUTO_CI" 2>&1

 ### Solution en multiples conteneur abandonnée...
# 	echo -e "\e[1m> Supprime les locks sur $change_version\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
# 	sudo rm -f "$new_CI_dir/package_check/pcheck.lock"
# 	sudo rm -f "$new_CI_dir/CI.lock"

 ### Solution en multiples conteneur abandonnée...
# 	echo -e "\e[1mCréer un lien symbolique pour le bot XMPP sur $change_version\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
# 	sudo rm -r "$new_CI_dir/auto_build/xmpp_bot" | tee -a "$LOG_BUILD_AUTO_CI"
# 	sudo ln -s "$script_dir/xmpp_bot" "$new_CI_dir/auto_build/xmpp_bot_diff" | tee -a "$LOG_BUILD_AUTO_CI"

 ### Solution en multiples conteneur abandonnée...
# 	echo -e "\e[1m> Ajoute un brige réseau pour la machine virtualisée\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
# 	echo | sudo tee /etc/network/interfaces.d/$change_LXC_BRIDGE <<EOF >> "$LOG_BUILD_AUTO_CI" 2>&1
# auto $change_LXC_BRIDGE
# iface $change_LXC_BRIDGE inet static
#         address $change_PLAGE_IP.1/24
#         bridge_ports none
#         bridge_fd 0
#         bridge_maxwait 0
# EOF

 ### Solution en multiples conteneur abandonnée...
# 	echo -e "\e[1m> Ajoute la config ssh pour $change_version\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
# 	echo | sudo tee -a /root/.ssh/config <<EOF >> "$LOG_BUILD_AUTO_CI" 2>&1
# # ssh $change_LXC_NAME
# Host $change_LXC_NAME
# Hostname $change_PLAGE_IP.2
# User pchecker
# IdentityFile /root/.ssh/$LXC_NAME
# EOF

 ### Solution en multiples conteneur abandonnée...
# 	echo -e "\e[1m> Création d'un snapshot pour le conteneur $change_version\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
# 	sudo lxc-snapshot -n $change_LXC_NAME >> "$LOG_BUILD_AUTO_CI" 2>&1

	echo -e "\e[1m> Ajout des tâches cron pour $change_version\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
	if [ "$change_version" == testing ]; then
		cron_hour=4	# Décale les horaires de maj de testing et unstable
	else
		cron_hour=5	# Pour que testing démarre ses tests avant unstable
	fi
	echo | sudo tee -a "/etc/cron.d/CI_package_check" <<EOF | tee -a "$LOG_BUILD_AUTO_CI"

## $change_version
# Vérifie les mises à jour du conteneur, à 4h30 chaque nuit.
30 $cron_hour * * * root "$script_dir/auto_upgrade_container.sh $change_version"
EOF
 ### Solution en multiples conteneur abandonnée...
# ## $change_version
# # Vérifie toutes les 5 minutes si un test doit être lancé avec Package_check
# */5 * * * * root "$new_CI_dir/pcheckCI.sh" >> "$new_CI_dir/pcheckCI.log" 2>&1
# # Vérifie les mises à jour du conteneur, à 4h30 chaque nuit.
# 30 $cron_hour * * * root "$new_CI_dir/package_check/sub_scripts/auto_upgrade.sh" >> "$new_CI_dir/package_check/upgrade.log" 2>&1
# # Vérifie chaque nuit les listes d'applications de Yunohost pour mettre à jour les jobs. À 4h10, après la maj du conteneur.
# 50 $cron_hour * * * root "$new_CI_dir/auto_build/list_app_ynh.sh" >> "$new_CI_dir/auto_build/update_lists.log" 2>&1
# EOF

 ### Solution en multiples conteneur abandonnée...
# 	echo -e "\e[1m> Modifie le trigger pour $change_version\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
# 	sudo cp -a "$new_CI_dir/auto_build/jenkins/jenkins_job_nostable.xml" "$new_CI_dir/auto_build/jenkins/jenkins_job.xml"

 ### Solution en multiples conteneur abandonnée...
# 	echo -e "\e[1m> Créer un lien symbolique pour les logs de $change_version\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
# 	# Les logs seront accessible depuis le dossier principal de logs.
# 	sudo ln -fs "$new_CI_dir/logs" "$parent_dir/CI_package_check/logs/logs_$change_version" | tee -a "$LOG_BUILD_AUTO_CI"
	mkdir "$script_dir/../logs/logs_$change_version"	# Créer le dossier des logs


 ### Solution en multiples conteneur abandonnée...
# 	# Créer un lien symbolique pour la liste des niveaux de stable. (Même si fichier n'existe pas encore)
# 	sudo ln -fs "$parent_dir/CI_package_check/auto_build/list_level_stable" "$new_CI_dir/auto_build/list_level_stable" | tee -a "$LOG_BUILD_AUTO_CI"

 ### Solution en multiples conteneur abandonnée...
# 	echo -e "\e[1m> Démarrage du bridge pour $change_version\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
# 	sudo ifup $change_LXC_BRIDGE --interfaces=/etc/network/interfaces.d/$change_LXC_BRIDGE | tee -a "$LOG_BUILD_AUTO_CI"

 ### Solution en multiples conteneur abandonnée...
# 	echo -e "\e[1m> Démarrage de la machine $change_version\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
# 	sudo lxc-start -n $change_LXC_NAME -d --logfile "$new_CI_dir/package_check/lxc_boot.log" >> "$LOG_BUILD_AUTO_CI" 2>&1
# 	sleep 3
# 	sudo lxc-ls -f >> "$LOG_BUILD_AUTO_CI" 2>&1

 ### Solution en multiples conteneur abandonnée...
# 	echo -e "\e[1m> Enregistre l'empreinte ECDSA pour la clé SSH\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
# 	sudo ssh-keyscan -H $change_PLAGE_IP.2 | sudo tee -a /root/.ssh/known_hosts >> "$LOG_BUILD_AUTO_CI" 2>&1
# 	ssh -t $change_LXC_NAME "exit 0"	# Initie une premier connexion SSH pour valider la clé.
# 	if [ "$?" -ne 0 ]; then	# Si l'utilisateur tarde trop, la connexion sera refusée...
# 		ssh -t $change_LXC_NAME "exit 0"
# 	fi
	# Pour une raison qui m'échappe encore, le ssh-keyscan ne semble pas passer. Il faudra donc se connecter manuellement pour valider les 2 nouveaux hosts.

# TESTING
# sudo ifup pcheck-testing --interfaces=/etc/network/interfaces.d/pcheck-testing
# sudo iptables -A FORWARD -i pcheck-testing -o eth0 -j ACCEPT
# sudo iptables -A FORWARD -i eth0 -o pcheck-testing -j ACCEPT
# sudo iptables -t nat -A POSTROUTING -s 10.1.5.0/24 -j MASQUERADE

# sudo lxc-start -n pcheck_testing -d
# sudo lxc-ls -f

# sudo ssh -t pcheck_testing "sudo ping -q -c 2 security.debian.org"

# sudo lxc-stop -n pcheck_testing
# sudo rsync -aEAX --delete -i /var/lib/lxcsnaps/pcheck_testing/snap0/rootfs/ /var/lib/lxc/pcheck_testing/rootfs/

# sudo iptables -D FORWARD -i pcheck-testing -o eth0 -j ACCEPT
# sudo iptables -D FORWARD -i eth0 -o pcheck-testing -j ACCEPT
# sudo iptables -t nat -D POSTROUTING -s 10.1.5.0/24 -j MASQUERADE
# sudo ifdown --force pcheck-testing

# UNSTABLE
# sudo ifup pcheck-unstable --interfaces=/etc/network/interfaces.d/pcheck-unstable
# sudo iptables -A FORWARD -i pcheck-unstable -o eth0 -j ACCEPT
# sudo iptables -A FORWARD -i eth0 -o pcheck-unstable -j ACCEPT
# sudo iptables -t nat -A POSTROUTING -s 10.1.6.0/24 -j MASQUERADE

# sudo lxc-start -n pcheck_unstable -d
# sudo lxc-ls -f

# sudo ssh -t pcheck_unstable "sudo ping -q -c 2 security.debian.org"

# sudo lxc-stop -n pcheck_unstable
# sudo rsync -aEAX --delete -i /var/lib/lxcsnaps/pcheck_unstable/snap0/rootfs/ /var/lib/lxc/pcheck_unstable/rootfs/

# sudo iptables -D FORWARD -i pcheck-unstable -o eth0 -j ACCEPT
# sudo iptables -D FORWARD -i eth0 -o pcheck-unstable -j ACCEPT
# sudo iptables -t nat -D POSTROUTING -s 10.1.6.0/24 -j MASQUERADE
# sudo ifdown --force pcheck-unstable

 ### Solution en multiples conteneur abandonnée...
# 	echo -e "\e[1m> Arrêt de la machine $change_version\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
# 	sudo lxc-stop -n $change_LXC_NAME >> "$LOG_BUILD_AUTO_CI" 2>&1

# 	echo -e "\e[1m> Arrêt du bridge pour $change_version\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
# 	sudo ifdown --force $change_LXC_BRIDGE | tee -a "$LOG_BUILD_AUTO_CI"

done

# Supprime les locks
sudo rm -f "$script_dir/../package_check/pcheck.lock"
sudo rm -f "$script_dir/../CI.lock"

 ### Solution en multiples conteneur abandonnée...
# echo -e "\e[1m> Les conteneurs testing et unstable seront mis à jour cette nuit.\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"

# Liste les apps Yunohost et créer les jobs à l'aide du script list_app_ynh.sh
echo -e "\e[1mCréation des jobs\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
sudo "$script_dir/list_app_ynh.sh"

echo -e "\e[1mVérification des droits d'accès\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
if sudo su -l $CI -c "ls \"$script_dir\"" > /dev/null 2<&1
then
	echo -e "\e[92mLes droits d'accès sont suffisant.\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
else
	echo -e "\e[91m$CI n'a pas les droits suffisants pour accéder aux scripts !\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
fi

echo ""
echo -e "\e[92mLe fichier $script_dir/xmpp_bot/password doit être renseigné avec le mot de passe du bot xmpp.\e[0m" | tee -a "$LOG_BUILD_AUTO_CI"
