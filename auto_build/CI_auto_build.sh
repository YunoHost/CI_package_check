#!/bin/bash

# Build a CI with YunoHost, Jenkins and CI_package_check
# Then add a build for each app.

# Get the path of this script
script_dir="$(dirname $(realpath $0))"

log_build_auto_ci="$script_dir/Log_build_auto_ci.log"
default_ci_user=ynhci

# This script can get as argument the domain for jenkins, the admin password of YunoHost and the type of installation requested.
# Domain for Jenkins
domain=$1
# Admin password of YunoHost
yuno_pwd=$2
# Type of CI to setup.
# Can be 'Mixed_content', 'Stable', 'Testing_Unstable' or 'ARM'
# Mixed_content is the old fashion CI with all the jobs in the same CI.
ci_type=$3

echo_bold () {
	echo -e "\e[1m$1\e[0m"	
}

# SPECIFIC PART FOR JENKINS (START)
SETUP_JENKINS () {
	# User which execute the CI software.
	ci_user=jenkins
	# Web path of the CI
	ci_path=jenkins

	echo_bold "> Installation of jenkins..." | tee -a "$log_build_auto_ci"
	sudo yunohost app install https://github.com/YunoHost-Apps/jenkins_ynh -a "domain=$domain&path=/$ci_path&is_public=1" | tee -a "$log_build_auto_ci"

	# Keep 1 simultaneous test only
	sudo sed -i "s/<numExecutors>.*</<numExecutors>1</" /var/lib/jenkins/config.xml

	# Set the default view.
	if [ "$ci_type" = "Mixed_content" ] || [ "$ci_type" = "Stable" ]
	then
		# Default view as "Stable" instead of "All"
		sudo sed -i "s/<primaryView>.*</<primaryView>Stable</" /var/lib/jenkins/config.xml
	elif [ "$ci_type" = "Testing_Unstable" ]
		# Default view as "Unstable" instead of "All"
		sudo sed -i "s/<primaryView>.*</<primaryView>Unstable</" /var/lib/jenkins/config.xml
	elif [ "$ci_type" = "ARM" ]
		# Default view as "ARM" instead of "All"
		sudo sed -i "s/<primaryView>.*</<primaryView>ARM</" /var/lib/jenkins/config.xml
	fi


	# Set up an ssh connection for jenkins cli.
	# Create a new ssh key.
	echo_bold "> Create a ssh key for jenkins-cli." | tee -a "$log_build_auto_ci"
	ssh-keygen -t rsa -b 4096 -N "" -f "$script_dir/jenkins/jenkins_key" > /dev/null | tee -a "$log_build_auto_ci"
	sudo chown root: "$script_dir/jenkins/jenkins_key" | tee -a "$log_build_auto_ci"
	sudo chmod 600 "$script_dir/jenkins/jenkins_key" | tee -a "$log_build_auto_ci"

	# Configure jenkins to use this ssh key.
	echo_bold "> Create a basic configuration for jenkins' user." | tee -a "$log_build_auto_ci"
	# Create a directory for this user.
	sudo mkdir -p "/var/lib/jenkins/users/$ci_user"
	# Copy the model of config.
	sudo cp "$script_dir/jenkins/user_config.xml" "/var/lib/jenkins/users/$ci_user/config.xml"
	# Add a name for this user.
	sudo sed -i "s/__USER__/$ci_user/g" "/var/lib/jenkins/users/$ci_user/config.xml" | tee -a "$log_build_auto_ci"
	# Add the ssh key
	sudo sed -i "s|__SSH_KEY__|$(cat "$script_dir/jenkins/jenkins_key.pub")|"  "/var/lib/jenkins/users/$ci_user/config.xml" | tee -a "$log_build_auto_ci"
	sudo chown jenkins: -R "/var/lib/jenkins/users"
	# Configure ssh port in jenkins config
	echo | sudo tee "/var/lib/jenkins/org.jenkinsci.main.modules.sshd.SSHD.xml" <<EOF | tee -a "$log_build_auto_ci"
<?xml version='1.0' encoding='UTF-8'?>
<org.jenkinsci.main.modules.sshd.SSHD>
  <port>0</port>
</org.jenkinsci.main.modules.sshd.SSHD>
EOF
	sudo chown jenkins: "/var/lib/jenkins/org.jenkinsci.main.modules.sshd.SSHD.xml" | tee -a "$log_build_auto_ci"

	# Reboot jenkins to consider the new key
	echo_bold "> Reboot jenkins to handle the new ssh key..." | tee -a "$log_build_auto_ci"
	sudo systemctl restart jenkins | tee -a "$log_build_auto_ci"

	tempfile="$(mktemp)"
	tail -f -n1 /var/log/jenkins/jenkins.log > "$tempfile" &	# Follow the boot of jenkins in its log
	pid_tail=$!	# get the PID of tail
	timeout=3600
	for i in `seq 1 $timeout`
	do	# Because it can be really long on a ARM architecture, wait until $timeout or the boot of jenkins.
		if grep -q "Jenkins is fully up and running" "$tempfile"; then
			echo "Jenkins has started correctly." | tee -a "$log_build_auto_ci"
			break
		fi
		sleep 1
	done
	kill -s 15 $pid_tail > /dev/null	# Stop tail
	sudo rm "$tempfile"
	if [ "$i" -ge $timeout ]; then
		echo "Jenkins hasn't started before the timeout (${timeout}s)." | tee -a "$log_build_auto_ci"
	fi


	# Add new views in jenkins
	jenkins_cli="sudo java -jar /var/lib/jenkins/jenkins-cli.jar -noCertificateCheck -s https://$domain/jenkins/ -i \"$script_dir/jenkins/jenkins_key\""
	echo_bold "> Add new views in jenkins" | tee -a "$log_build_auto_ci"
	if [ "$ci_type" = "Mixed_content" ] || [ "$ci_type" = "Stable" ]
	then
		$jenkins_cli create-view Official < "$script_dir/jenkins/Views_official.xml"
		$jenkins_cli create-view Community < "$script_dir/jenkins/Views_community.xml"
		$jenkins_cli create-view Stable < "$script_dir/jenkins/Views_stable.xml"
	fi
	if [ "$ci_type" = "Mixed_content" ] || [ "$ci_type" = "Testing_Unstable" ]
	then
		$jenkins_cli create-view Testing < "$script_dir/jenkins/Views_testing.xml"
		$jenkins_cli create-view Unstable < "$script_dir/jenkins/Views_unstable.xml"
	fi
	if [ "$ci_type" = "Mixed_content" ] || [ "$ci_type" = "ARM" ]
	then
		$jenkins_cli create-view "Raspberry Pi" < "$script_dir/jenkins/Views_arm.xml"
	fi


	# Put jenkins as the default app on the root of the domain
	sudo yunohost app makedefault -d "$domain" jenkins
}
# SPECIFIC PART FOR JENKINS (END)


SETUP_CI_APP () {
	# Setting up of a CI software as a frontend.
	# To change the software, add a new function for it and replace the following call.
	SETUP_JENKINS
}



# Install YunoHost
echo_bold "> Check if YunoHost is already installed." | tee "$log_build_auto_ci"
if [ ! -e /usr/bin/yunohost ]
then
	echo_bold "> YunoHost isn't yet installed." | tee "$log_build_auto_ci"
	echo_bold "Installation of YunoHost..." | tee "$log_build_auto_ci"
	sudo apt-get update | tee "$log_build_auto_ci" 2>&1
	sudo apt-get install -y sudo git | tee "$log_build_auto_ci" 2>&1
	git clone https://github.com/YunoHost/install_script /tmp/install_script
	cd /tmp/install_script; sudo ./install_yunohost -a | tee "$log_build_auto_ci" 2>&1

	echo_bold "> YunoHost post install" | tee -a "$log_build_auto_ci"
	if [ -n "$domain" ]; then
		domain_arg="--domain $domain"
	else
		domain_arg=""
	fi
		if [ -n "$yuno_pwd" ]; then
			pass_arg="--password $yuno_pwd"
		else
			pass_arg=""
		fi
	sudo yunohost tools postinstall $domain_arg $pass_arg
fi


# Get the first available domain if no domain is defined.
if [ -z "$domain" ]; then
	domain=$(sudo yunohost domain list --output-as plain | head -n1)
fi

# Fill out /etc/hosts with the domain name
echo "127.0.0.1 $domain	#CI_APP" | sudo tee -a /etc/hosts


if [ -n "$yuno_pwd" ]; then
	pass_arg="--admin-password $yuno_pwd"
else
	pass_arg=""
fi

# Check if the user already exist
if ! sudo yunohost user list --output-as json $pass_arg | grep -q "\"username\": \"$ci_user\""
then
	if [ -n "$yuno_pwd" ]; then
		pass_arg="--password $yuno_pwd --admin-password $yuno_pwd"
	else
		pass_arg=""
	fi
	echo_bold "> Create a YunoHost user" | tee -a "$log_build_auto_ci"
	sudo yunohost user create --firstname "$ci_user" --mail "$ci_user@$domain" --lastname "$ci_user" "$ci_user" $pass_arg
fi



# Installation of the CI software, which be used as the main interface.
SETUP_CI_APP

XXX

echo_bold "Mise en place de Package check à l'aide des scripts d'intégration continue" | tee -a "$log_build_auto_ci"
"$script_dir/../build_CI.sh" #| tee -a "$log_build_auto_ci" 2>&1

# Met en place les locks pour éviter des démarrages intempestifs durant le build
touch "$script_dir/../CI.lock"
touch "$script_dir/../package_check/pcheck.lock"

# Déplace le snapshot et le remplace par un lien symbolique
echo_bold "Remplacement du snapshot par un lien symbolique" | tee -a "$log_build_auto_ci"
LXC_NAME=$(cat "$script_dir/../package_check/config" | grep LXC_NAME= | cut -d '=' -f2)
sudo mv /var/lib/lxcsnaps/$LXC_NAME /var/lib/lxcsnaps/pcheck_stable
sudo ln -s /var/lib/lxcsnaps/pcheck_stable /var/lib/lxcsnaps/$LXC_NAME

# Modifie la tâche cron pour utiliser auto_upgrade_container
echo_bold "Modification de la tâche cron pour l'upgrade" | tee -a "$log_build_auto_ci"
sudo sed -i "s@package_check/sub_scripts/auto_upgrade.sh.*@auto_build/auto_upgrade_container.sh\" stable@g" "/etc/cron.d/CI_package_check" | tee -a "$log_build_auto_ci"

 ### Solution en multiples conteneur abandonnée en raison d'une erreur récurente "curl: (7) Failed to connect to sous.domain.tld port 80: No route to host"
# echo_bold "Clone le conteneur LXC pour la version testing" | tee -a "$log_build_auto_ci"
# LXC_NAME=$(cat "$script_dir/../package_check/sub_scripts/lxc_build.sh" | grep LXC_NAME= | cut -d '=' -f2)
# sudo lxc-copy --name=$LXC_NAME --newname=pcheck_testing | tee -a "$log_build_auto_ci"

# Met en place le cron pour maintenir à jour la liste des jobs. Et le cron pour changer le niveau des apps
echo_bold "Ajout de la tâche cron" | tee -a "$log_build_auto_ci"
cat "$script_dir/CI_package_check_cron" | sudo tee -a "/etc/cron.d/CI_package_check" > /dev/null	# Ajoute le cron à la suite du cron de CI déjà en place.
sudo sed -i "s@__PATH__@$script_dir@g" "/etc/cron.d/CI_package_check"	# Renseigne l'emplacement du script dans le cron

# Modifie la config nginx pour ajouter l'accès aux logs
echo | sudo tee -a "/etc/nginx/conf.d/$domain.d/$CI_PATH.conf" <<EOF | tee -a "$log_build_auto_ci"
location /$CI_PATH/logs {
   alias $(dirname "$script_dir")/logs/;
   autoindex on;
}
EOF

# Créer le fichier de configuration
echo | sudo tee "$script_dir/auto.conf" <<EOF | tee -a "$log_build_auto_ci"
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
domain=$domain
}
EOF
echo_bold "Le fichier de configuration a été créée dans $script_dir/auto.conf" | tee -a "$log_build_auto_ci"

echo_bold "Mise en place du bot XMPP" | tee -a "$log_build_auto_ci"
sudo apt-get install python-xmpp | tee -a "$log_build_auto_ci"
git clone https://github.com/YunoHost/weblate2xmpp "$script_dir/xmpp_bot" | tee -a "$log_build_auto_ci"
sudo touch "$script_dir/xmpp_bot/password" | tee -a "$log_build_auto_ci"
sudo chmod 600 "$script_dir/xmpp_bot/password" | tee -a "$log_build_auto_ci"
echo "python \"$script_dir/xmpp_bot/to_room.py\" \$(sudo cat \"$script_dir/xmpp_bot/password\") \"\$@\" apps" \
> "$script_dir/xmpp_bot/xmpp_post.sh" | tee -a "$log_build_auto_ci"
sudo chmod +x "$script_dir/xmpp_bot/xmpp_post.sh" | tee -a "$log_build_auto_ci"

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
# 		echo_bold "Clone le conteneur testing pour la version unstable" | tee -a "$log_build_auto_ci"
# 		sudo lxc-copy --name=pcheck_testing --newname=pcheck_unstable >> "$log_build_auto_ci" 2>&1
# 	else
# 		change_PLAGE_IP="10.1.6"
# 	fi

 ### Solution en multiples conteneur abandonnée...
# 	echo_bold "> Modification de l'ip de la version $change_version" | tee -a "$log_build_auto_ci"
# 	sudo sed -i "s@$PLAGE_IP@$change_PLAGE_IP@" /var/lib/lxc/$change_LXC_NAME/rootfs/etc/network/interfaces >> "$log_build_auto_ci" 2>&1
# 	echo_bold "> Le nom du veth" | tee -a "$log_build_auto_ci"
# 	sudo sed -i "s@^lxc.network.veth.pair = ${LXC_NAME}@lxc.network.veth.pair = $change_LXC_NAME@" /var/lib/lxc/$change_LXC_NAME/config >> "$log_build_auto_ci" 2>&1
# 	echo_bold "> Et le nom du bridge" | tee -a "$log_build_auto_ci"
# 	sudo sed -i "s@^lxc.network.link = ${LXC_BRIDGE}@lxc.network.link = $change_LXC_BRIDGE@" /var/lib/lxc/$change_LXC_NAME/config >> "$log_build_auto_ci" 2>&1
# 	echo_bold "> Et enfin renseigne /etc/hosts sur $change_version" | tee -a "$log_build_auto_ci"
# 	sudo sed -i "s@^127.0.0.1 ${LXC_NAME}@127.0.0.1 $change_LXC_NAME@" /var/lib/lxc/$change_LXC_NAME/rootfs/etc/hosts >> "$log_build_auto_ci" 2>&1

	# Créer le dossier pour le snapshot
	sudo mkdir /var/lib/lxcsnaps/pcheck_$change_version
	echo_bold "> Duplique le snapshot stable vers $change_version" | tee -a "$log_build_auto_ci"
	sudo cp -a /var/lib/lxcsnaps/pcheck_stable/snap0 /var/lib/lxcsnaps/pcheck_$change_version/snap0

	echo_bold "> Configure les dépôts du conteneur sur $change_version" | tee -a "$log_build_auto_ci"
	if [ $change_version == testing ]; then
		source="testing"
	else
		source="testing unstable"
	fi
	sudo echo "deb http://repo.yunohost.org/debian/ jessie stable $source" | sudo tee  /var/lib/lxcsnaps/pcheck_$change_version/snap0/rootfs/etc/apt/sources.list.d/yunohost.list >> "$log_build_auto_ci" 2>&1

	# Supprime les locks pour autoriser l'upgrade
	sudo rm -f "$script_dir/../package_check/pcheck.lock" "$script_dir/../CI.lock"

	echo_bold "> Effectue la mise à jour du conteneur sur $change_version" | tee -a "$log_build_auto_ci"
	sudo "$script_dir/auto_upgrade_container.sh" $change_version | tee -a "$log_build_auto_ci"

	# Remet les locks après l'upgrade
	touch "$script_dir/../CI.lock" "$script_dir/../package_check/pcheck.lock"

 ### Solution en multiples conteneur abandonnée...
# 	echo_bold "> Créer une copie des scripts CI_package_check pour $change_version" | tee -a "$log_build_auto_ci"
# 	parent_dir="$(echo "$(dirname "$(dirname "$script_dir")")")"
# 	new_CI_dir="$parent_dir/CI_package_check_$change_version"
# 	sudo cp -a "$parent_dir/CI_package_check" "$new_CI_dir"
# 	echo_bold "> Modifie les infos du conteneur dans le script build" | tee -a "$log_build_auto_ci"
 ### Solution en multiples conteneur abandonnée...
# 	sudo sed -i "s@^PLAGE_IP=.*@PLAGE_IP=\"$change_PLAGE_IP\"@" "$new_CI_dir/package_check/sub_scripts/lxc_build.sh" >> "$log_build_auto_ci" 2>&1
# 	sudo sed -i "s@^LXC_NAME=.*@LXC_NAME=$change_LXC_NAME@" "$new_CI_dir/package_check/sub_scripts/lxc_build.sh" >> "$log_build_auto_ci" 2>&1
# 	sudo sed -i "s@^LXC_BRIDGE=.*@LXC_BRIDGE=$change_LXC_BRIDGE@" "$new_CI_dir/package_check/sub_scripts/lxc_build.sh" >> "$log_build_auto_ci" 2>&1

 ### Solution en multiples conteneur abandonnée...
# 	echo_bold "> Supprime les locks sur $change_version" | tee -a "$log_build_auto_ci"
# 	sudo rm -f "$new_CI_dir/package_check/pcheck.lock"
# 	sudo rm -f "$new_CI_dir/CI.lock"

 ### Solution en multiples conteneur abandonnée...
# 	echo_bold "Créer un lien symbolique pour le bot XMPP sur $change_version" | tee -a "$log_build_auto_ci"
# 	sudo rm -r "$new_CI_dir/auto_build/xmpp_bot" | tee -a "$log_build_auto_ci"
# 	sudo ln -s "$script_dir/xmpp_bot" "$new_CI_dir/auto_build/xmpp_bot_diff" | tee -a "$log_build_auto_ci"

 ### Solution en multiples conteneur abandonnée...
# 	echo_bold "> Ajoute un brige réseau pour la machine virtualisée" | tee -a "$log_build_auto_ci"
# 	echo | sudo tee /etc/network/interfaces.d/$change_LXC_BRIDGE <<EOF >> "$log_build_auto_ci" 2>&1
# auto $change_LXC_BRIDGE
# iface $change_LXC_BRIDGE inet static
#         address $change_PLAGE_IP.1/24
#         bridge_ports none
#         bridge_fd 0
#         bridge_maxwait 0
# EOF

 ### Solution en multiples conteneur abandonnée...
# 	echo_bold "> Ajoute la config ssh pour $change_version" | tee -a "$log_build_auto_ci"
# 	echo | sudo tee -a /root/.ssh/config <<EOF >> "$log_build_auto_ci" 2>&1
# # ssh $change_LXC_NAME
# Host $change_LXC_NAME
# Hostname $change_PLAGE_IP.2
# User pchecker
# IdentityFile /root/.ssh/$LXC_NAME
# EOF

 ### Solution en multiples conteneur abandonnée...
# 	echo_bold "> Création d'un snapshot pour le conteneur $change_version" | tee -a "$log_build_auto_ci"
# 	sudo lxc-snapshot -n $change_LXC_NAME >> "$log_build_auto_ci" 2>&1

	echo_bold "> Ajout des tâches cron pour $change_version" | tee -a "$log_build_auto_ci"
	if [ "$change_version" == testing ]; then
		cron_hour=4	# Décale les horaires de maj de testing et unstable
	else
		cron_hour=5	# Pour que testing démarre ses tests avant unstable
	fi
	echo | sudo tee -a "/etc/cron.d/CI_package_check" <<EOF | tee -a "$log_build_auto_ci"

## $change_version
# Vérifie les mises à jour du conteneur, à 4h30 chaque nuit.
30 $cron_hour * * * root "$script_dir/auto_upgrade_container.sh" $change_version
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
# 	echo_bold "> Modifie le trigger pour $change_version" | tee -a "$log_build_auto_ci"
# 	sudo cp -a "$new_CI_dir/auto_build/jenkins/jenkins_job_nostable.xml" "$new_CI_dir/auto_build/jenkins/jenkins_job.xml"

 ### Solution en multiples conteneur abandonnée...
# 	echo_bold "> Créer un lien symbolique pour les logs de $change_version" | tee -a "$log_build_auto_ci"
# 	# Les logs seront accessible depuis le dossier principal de logs.
# 	sudo ln -fs "$new_CI_dir/logs" "$parent_dir/CI_package_check/logs/logs_$change_version" | tee -a "$log_build_auto_ci"
	mkdir "$script_dir/../logs/logs_$change_version"	# Créer le dossier des logs


 ### Solution en multiples conteneur abandonnée...
# 	# Créer un lien symbolique pour la liste des niveaux de stable. (Même si fichier n'existe pas encore)
# 	sudo ln -fs "$parent_dir/CI_package_check/auto_build/list_level_stable" "$new_CI_dir/auto_build/list_level_stable" | tee -a "$log_build_auto_ci"

 ### Solution en multiples conteneur abandonnée...
# 	echo_bold "> Démarrage du bridge pour $change_version" | tee -a "$log_build_auto_ci"
# 	sudo ifup $change_LXC_BRIDGE --interfaces=/etc/network/interfaces.d/$change_LXC_BRIDGE | tee -a "$log_build_auto_ci"

 ### Solution en multiples conteneur abandonnée...
# 	echo_bold "> Démarrage de la machine $change_version" | tee -a "$log_build_auto_ci"
# 	sudo lxc-start -n $change_LXC_NAME -d --logfile "$new_CI_dir/package_check/lxc_boot.log" >> "$log_build_auto_ci" 2>&1
# 	sleep 3
# 	sudo lxc-ls -f >> "$log_build_auto_ci" 2>&1

 ### Solution en multiples conteneur abandonnée...
# 	echo_bold "> Enregistre l'empreinte ECDSA pour la clé SSH" | tee -a "$log_build_auto_ci"
# 	sudo ssh-keyscan -H $change_PLAGE_IP.2 | sudo tee -a /root/.ssh/known_hosts >> "$log_build_auto_ci" 2>&1
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
# 	echo_bold "> Arrêt de la machine $change_version" | tee -a "$log_build_auto_ci"
# 	sudo lxc-stop -n $change_LXC_NAME >> "$log_build_auto_ci" 2>&1

# 	echo_bold "> Arrêt du bridge pour $change_version" | tee -a "$log_build_auto_ci"
# 	sudo ifdown --force $change_LXC_BRIDGE | tee -a "$log_build_auto_ci"

done

# Supprime les locks
sudo rm -f "$script_dir/../package_check/pcheck.lock"
sudo rm -f "$script_dir/../CI.lock"

 ### Solution en multiples conteneur abandonnée...
# echo_bold "> Les conteneurs testing et unstable seront mis à jour cette nuit." | tee -a "$log_build_auto_ci"

# Liste les apps Yunohost et créer les jobs à l'aide du script list_app_ynh.sh
echo_bold "Création des jobs" | tee -a "$log_build_auto_ci"
sudo "$script_dir/list_app_ynh.sh"

echo_bold "Vérification des droits d'accès" | tee -a "$log_build_auto_ci"
if sudo su -l $CI -c "ls \"$script_dir\"" > /dev/null 2<&1
then
	echo -e "\e[92mLes droits d'accès sont suffisant." | tee -a "$log_build_auto_ci"
else
	echo -e "\e[91m$CI n'a pas les droits suffisants pour accéder aux scripts !" | tee -a "$log_build_auto_ci"
fi

echo ""
echo -e "\e[92mLe fichier $script_dir/xmpp_bot/password doit être renseigné avec le mot de passe du bot xmpp.\e[0m" | tee -a "$log_build_auto_ci"
