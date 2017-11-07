#!/bin/bash

# Active patches for scaleway...
scaleway=1


script_dir="$(dirname $(realpath $0))"

log_build="$script_dir/Log_build_dev_ci.log"
ci_user=ynhci

domain=$1
yuno_pwd=$2

# JENKINS
SETUP_JENKINS () {
	ci=jenkins	# Utilisateur avec lequel s'exécute jenkins
	ci_path=jenkins

	echo -e "\e[1m> Installation de jenkins...\e[0m" | tee -a "$log_build"
	sudo yunohost app install https://github.com/YunoHost-Apps/jenkins_ynh -a "domain=$domain&path=/$ci_path&is_public=1" | tee -a "$log_build"

	# Réduit le nombre de tests simultanés à 1 sur jenkins
	sudo sed -i "s/<numExecutors>.*</<numExecutors>1</" /var/lib/jenkins/config.xml

	# Mise en place de la connexion ssh pour jenkins cli.
	# Création de la clé ssh
	echo -e "\e[1m> Créer la clé ssh pour jenkins-cli.\e[0m" | tee -a "$log_build"
	ssh-keygen -t rsa -b 4096 -N "" -f "$script_dir/jenkins/jenkins_key" > /dev/null | tee -a "$log_build"
	sudo chown root: "$script_dir/jenkins/jenkins_key" | tee -a "$log_build"
	sudo chmod 600 "$script_dir/jenkins/jenkins_key" | tee -a "$log_build"

	# Configuration de la clé pour l'user dans jenkins
	echo -e "\e[1m> Créer la base de la configuration de l'utilisateur jenkins.\e[0m" | tee -a "$log_build"
	sudo mkdir -p "/var/lib/jenkins/users/$ci_user"	# Créer le dossier de l'utilisateur
	sudo cp "$script_dir/jenkins/user_config.xml" "/var/lib/jenkins/users/$ci_user/config.xml"	# Copie la config de base.
	sudo sed -i "s/__USER__/$ci_user/g" "/var/lib/jenkins/users/$ci_user/config.xml" | tee -a "$log_build"	# Ajoute le nom de l'utilisateur
	sudo sed -i "s|__SSH_KEY__|$(cat "$script_dir/jenkins/jenkins_key.pub")|"  "/var/lib/jenkins/users/$ci_user/config.xml" | tee -a "$log_build"	# Ajoute la clé publique
	sudo chown jenkins: -R "/var/lib/jenkins/users"

	# Configure le port ssh sur jenkins
	echo | sudo tee "/var/lib/jenkins/org.jenkinsci.main.modules.sshd.SSHD.xml" <<EOF | tee -a "$log_build"
<?xml version='1.0' encoding='UTF-8'?>
<org.jenkinsci.main.modules.sshd.SSHD>
  <port>0</port>
</org.jenkinsci.main.modules.sshd.SSHD>
EOF
	sudo chown jenkins: "/var/lib/jenkins/org.jenkinsci.main.modules.sshd.SSHD.xml" | tee -a "$log_build"

	# Copie la configuration de AnsiColor
	sudo cp "$script_dir/../auto_build/jenkins/hudson.plugins.ansicolor.AnsiColorBuildWrapper.xml" /var/lib/jenkins/

	echo -e "\e[1m> Redémarre jenkins pour prendre en compte la clé ssh...\e[0m" | tee -a "$log_build"
	sudo service jenkins restart | tee -a "$log_build"

	tempfile="$(mktemp)"
	tail -f -n1 /var/log/jenkins/jenkins.log > "$tempfile" &	# Suit le démarrage dans le log
	pid_tail=$!	# Récupère le PID de la commande tail, qui est passée en arrière plan.
	timeout=3600
	for i in `seq 1 $timeout`
	do	# La boucle attend le démarrage de jenkins Ou $timeout (Le démarrage sur arm est trèèèèèèèèès long...).
		if grep -q "Jenkins is fully up and running" "$tempfile"; then
			echo "Jenkins a démarré correctement." | tee -a "$log_build"
			break
		fi
		sleep 5
	done
	kill -s 15 $pid_tail > /dev/null	# Arrête l'exécution de tail.
	sudo rm "$tempfile"
	if [ "$i" -ge $timeout ]; then
		echo "Jenkins n'a pas démarré dans le temps imparti." | tee -a "$log_build"
	fi

	# Passe l'application à la racine du domaine
	sudo yunohost app makedefault -d "$domain" jenkins
}
# / JENKINS

SETUP_CI_APP () {
	# Installation du logiciel de CI qui servira d'interface
	# Pour changer de logiciel, ajouter simplement une fonction et changer l'appel qui suit.
	SETUP_JENKINS
}

echo -e "\e[1m> Vérifie que YunoHost est déjà installé.\e[0m" | tee "$log_build"
if [ ! -e /usr/bin/yunohost ]
then
	echo -e "\e[1m> YunoHost n'est pas installé.\e[0m" | tee "$log_build"
	echo -e "\e[1mInstallation de YunoHost...\e[0m" | tee "$log_build"
	sudo apt-get update | tee "$log_build" 2>&1
	sudo apt-get install -y sudo git | tee "$log_build" 2>&1
	git clone https://github.com/YunoHost/install_script /tmp/install_script
	cd /tmp/install_script; sudo ./install_yunohost -a | tee "$log_build" 2>&1

	echo -e "\e[1m> Post install Yunohost\e[0m" | tee -a "$log_build"
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

if [ -z "$domain" ]; then
	domain=$(sudo yunohost domain list | grep -m1 "-" | awk '{print $2}')	# Récupère le premier domaine disponible dans Yunohost
fi

echo "127.0.0.1 $domain	#CI_APP" | sudo tee -a /etc/hosts	# Renseigne le domain dans le host

if [ -n "$yuno_pwd" ]; then
        pass_arg="--admin-password $yuno_pwd"
else
        pass_arg=""
fi

if ! sudo yunohost user list --output-as json $pass_arg | grep -q "\"username\": \"$ci_user\""	# Vérifie si l'utilisateur existe
then
	if [ -n "$yuno_pwd" ]; then
		pass_arg="--password $yuno_pwd --admin-password $yuno_pwd"
	else
		pass_arg=""
	fi
	echo -e "\e[1m> Création de l'utilisateur YunoHost $ci_user\e[0m" | tee -a "$log_build"
	sudo yunohost user create --firstname "$ci_user" --mail "$ci_user@$domain" --lastname "$ci_user" "$ci_user" $pass_arg
fi

# Installation du logiciel de CI qui servira d'interface
SETUP_CI_APP

echo -e "\e[1mMise en place de Package check à l'aide des scripts d'intégration continue\e[0m" | tee -a "$log_build"
"$script_dir/../build_CI.sh"


# ALERT
if [ $scaleway -eq 1 ]
then
	# With scaleway, there an issue with the dns.
	# So, change the dns
	sudo sed -i "s@dns=.*@dns=208.67.222.222@g" "$script_dir/../package_check/config"
	# Then rebuild the container
	"$script_dir/../package_check/sub_scripts/lxc_build.sh"
fi
# ALERT


# Met en place les locks pour éviter des démarrages intempestifs durant le build
touch "$script_dir/../CI.lock"
touch "$script_dir/../package_check/pcheck.lock"

# Modifie la config nginx pour ajouter l'accès aux logs
echo | sudo tee -a "/etc/nginx/conf.d/$domain.d/$ci_path.conf" <<EOF | tee -a "$log_build"
location /$ci_path/logs {
   alias $(dirname "$script_dir")/logs/;
   autoindex on;
}
EOF

# Créer le fichier de configuration
echo | sudo tee "$script_dir/config.conf" <<EOF | tee -a "$log_build"
# Path du logiciel de CI
CI_PATH=$ci_path

# Domaine utilisé
DOMAIN=$domain
}
EOF

# Supprime les locks
sudo rm -f "$script_dir/../package_check/pcheck.lock"
sudo rm -f "$script_dir/../CI.lock"

echo -e "\e[1mVérification des droits d'accès\e[0m" | tee -a "$log_build"
if sudo su -l $ci -c "ls \"$script_dir\"" > /dev/null 2<&1
then
	echo -e "\e[92mLes droits d'accès sont suffisant.\e[0m" | tee -a "$log_build"
else
	echo -e "\e[91m$ci n'a pas les droits suffisants pour accéder aux scripts !\e[0m" | tee -a "$log_build"
fi


# ALERT
if [ $scaleway -eq 1 ]
then
	# With scaleway, there no fstab...
	# So, we will build it...
	uuid_vda=$(sudo blkid /dev/vda -o value -s UUID)
	echo "UUID=$uuid_vda /     ext4    rw,relatime,data=ordered        0       1" >> /etc/fstab
fi
# ALERT


# Installation de ssh_chroot_dir
sudo yunohost app install https://github.com/YunoHost-Apps/ssh_chroot_dir_ynh -a "ssh_user=base_user&password=""&pub_key=fake_key&size=1G" --verbose | tee -a "$log_build"

# Créer un lien symbolique pour un accès facile à chroot_manager
ln -sf /home/yunohost.app/ssh_chroot_directories/chroot_manager ./chroot_manager
# Et à l'ajout d'utilisateur.
ln -sf "$script_dir/Add_a_new_user.sh" ./Add_a_new_user.sh

# Ajout des tâches cron
echo -e "\e[1mAjout des tâches cron\e[0m" | tee -a "$log_build"
cat "$script_dir/CI_package_check_cron" | sudo tee -a "/etc/cron.d/CI_package_check" > /dev/null	# Ajoute le cron à la suite du cron de CI déjà en place.
sudo sed -i "s@__PATH__@$script_dir@g" "/etc/cron.d/CI_package_check"	# Renseigne l'emplacement du script dans le cron
