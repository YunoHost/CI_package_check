#!/bin/bash

# Build a CI with YunoHost, Jenkins and CI_package_check
# Then add a build for each app.

# Get the path of this script
script_dir="$(dirname $(realpath $0))"

script_dir_name="$(basename $(realpath $script_dir/../))"

log_build_auto_ci="$script_dir/Log_build_auto_ci.log"
tee_to_log="tee -a $log_build_auto_ci 2>&1"
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
if [ -z "$ci_type" ]
then
	echo "Please choose the type of CI to build"
	echo -e "\t1) Mixed content (All type in one CI)"
	echo -e "\t2) Stable only"
	echo -e "\t3) Testing and unstable"
	echo -e "\t4) Deported ARM"
	echo -e "\t5) Jessie"
	read -p "?: " answer
fi
case $answer in
	1) ci_type=Mixed_content ;;
	2) ci_type=Stable ;;
	3) ci_type=Testing_Unstable ;;
	4) ci_type=ARM ;;
	5) ci_type=Next_debian ;;
	*) echo "CI type not defined !"; exit 1
esac

echo_bold () {
	echo -e "\e[1m$1\e[0m" | $tee_to_log
}

# SPECIFIC PART FOR JENKINS (START)
SETUP_JENKINS () {
	# User which execute the CI software.
	ci_user=jenkins
	# Web path of the CI
	ci_path=ci

	echo_bold "> Installation of jenkins..."
	sudo yunohost app install --force https://github.com/YunoHost-Apps/jenkins_ynh -a "domain=$domain&path=/$ci_path&is_public=1" | $tee_to_log

	# Keep 1 simultaneous test only
	sudo sed -i "s/<numExecutors>.*</<numExecutors>1</" /var/lib/jenkins/config.xml | $tee_to_log

	# Set the default view.
	if [ "$ci_type" = "Mixed_content" ] || [ "$ci_type" = "Stable" ]
	then
		# Default view as "Stable" instead of "All"
		sudo sed -i "s/<primaryView>.*</<primaryView>Stable</" /var/lib/jenkins/config.xml | $tee_to_log
	elif [ "$ci_type" = "Testing_Unstable" ]
	then
		# Default view as "Unstable" instead of "All"
		sudo sed -i "s/<primaryView>.*</<primaryView>Unstable</" /var/lib/jenkins/config.xml | $tee_to_log
	elif [ "$ci_type" = "ARM" ]
	then
		# Default view as "ARM" instead of "All"
		sudo sed -i "s/<primaryView>.*</<primaryView>ARM</" /var/lib/jenkins/config.xml | $tee_to_log
	fi


	# Set up an ssh connection for jenkins cli.
	# Create a new ssh key.
	echo_bold "> Create a ssh key for jenkins-cli."
	ssh-keygen -t rsa -b 4096 -N "" -f "$script_dir/jenkins/jenkins_key" > /dev/null
	sudo chown root: "$script_dir/jenkins/jenkins_key" | $tee_to_log
	sudo chmod 600 "$script_dir/jenkins/jenkins_key" | $tee_to_log

	# Configure jenkins to use this ssh key.
	echo_bold "> Create a basic configuration for jenkins' user."
	# Create a directory for this user.
	sudo mkdir -p "/var/lib/jenkins/users/$default_ci_user" | $tee_to_log
	# Copy the model of config.
	sudo cp "$script_dir/jenkins/user_config.xml" "/var/lib/jenkins/users/$default_ci_user/config.xml" | $tee_to_log
	# Add a name for this user.
	sudo sed -i "s/__USER__/$default_ci_user/g" "/var/lib/jenkins/users/$default_ci_user/config.xml" | $tee_to_log
	# Add the ssh key
	sudo sed -i "s|__SSH_KEY__|$(cat "$script_dir/jenkins/jenkins_key.pub")|"  "/var/lib/jenkins/users/$default_ci_user/config.xml" | $tee_to_log
	sudo chown jenkins: -R "/var/lib/jenkins/users" | $tee_to_log
	# Configure ssh port in jenkins config
	echo | sudo tee "/var/lib/jenkins/org.jenkinsci.main.modules.sshd.SSHD.xml" <<EOF | $tee_to_log
<?xml version='1.0' encoding='UTF-8'?>
<org.jenkinsci.main.modules.sshd.SSHD>
  <port>0</port>
</org.jenkinsci.main.modules.sshd.SSHD>
EOF
	sudo chown jenkins: "/var/lib/jenkins/org.jenkinsci.main.modules.sshd.SSHD.xml" | $tee_to_log

	# Copy AnsiColor configuration
	sudo cp "$script_dir/jenkins/hudson.plugins.ansicolor.AnsiColorBuildWrapper.xml" /var/lib/jenkins/

	# Reboot jenkins to consider the new key
	echo_bold "> Reboot jenkins to handle the new ssh key..."
	sudo systemctl restart jenkins | $tee_to_log

	tempfile="$(mktemp)"
	tail -f -n1 /var/log/jenkins/jenkins.log > "$tempfile" &	# Follow the boot of jenkins in its log
	pid_tail=$!	# get the PID of tail
	timeout=3600
	for i in `seq 1 $timeout`
	do	# Because it can be really long on a ARM architecture, wait until $timeout or the boot of jenkins.
		if grep -q "Jenkins is fully up and running" "$tempfile"; then
			echo "Jenkins has started correctly." | $tee_to_log
			break
		fi
		sleep 1
	done
	kill -s 15 $pid_tail > /dev/null	# Stop tail
	sudo rm "$tempfile" | $tee_to_log
	if [ "$i" -ge $timeout ]; then
		echo "Jenkins hasn't started before the timeout (${timeout}s)." | $tee_to_log
	fi


	# Add new views in jenkins
	jenkins_cli="sudo java -jar /var/lib/jenkins/jenkins-cli.jar -ssh -user $default_ci_user -noCertificateCheck -s https://$domain/jenkins/ -i $script_dir/jenkins/jenkins_key"
	echo_bold "> Add new views in jenkins"
	$jenkins_cli create-view Official < "$script_dir/jenkins/Views_official.xml" | $tee_to_log
	$jenkins_cli create-view Community < "$script_dir/jenkins/Views_community.xml" | $tee_to_log
	if [ "$ci_type" = "Mixed_content" ] || [ "$ci_type" = "Stable" ]
	then
		$jenkins_cli create-view Stable < "$script_dir/jenkins/Views_stable.xml" | $tee_to_log
	fi
	if [ "$ci_type" = "Mixed_content" ] || [ "$ci_type" = "Testing_Unstable" ]
	then
		$jenkins_cli create-view Testing < "$script_dir/jenkins/Views_testing.xml" | $tee_to_log
		$jenkins_cli create-view Unstable < "$script_dir/jenkins/Views_unstable.xml" | $tee_to_log
	fi
	if [ "$ci_type" = "Mixed_content" ] || [ "$ci_type" = "ARM" ]
	then
		$jenkins_cli create-view "Raspberry Pi" < "$script_dir/jenkins/Views_arm.xml" | $tee_to_log
	fi


	# Install aditionnal plugins
	$jenkins_cli install-plugin naginator | $tee_to_log	# Rerun failed plugins
	$jenkins_cli install-plugin greenballs | $tee_to_log	# Green ball instead of blue
	$jenkins_cli install-plugin embeddable-build-status | $tee_to_log	# Give small pictures with status of builds.

	# Restart for integrate new plugins
	sudo systemctl restart jenkins | $tee_to_log

	# Put jenkins as the default app on the root of the domain
	sudo yunohost app makedefault -d "$domain" jenkins | $tee_to_log

	# Add an access to logs in the nginx config
	echo | sudo tee -a "/etc/nginx/conf.d/$domain.d/$ci_path.conf" <<EOF | $tee_to_log
location /$ci_path/logs {
	alias $(dirname "$script_dir")/logs/;
	autoindex on;
}
EOF
	sudo systemctl reload nginx
}
# SPECIFIC PART FOR JENKINS (END)

# SPECIFIC PART FOR YUNORUNNER (START)
SETUP_YUNORUNNER () {
	# User which execute the CI software.
	ci_user=yunorunner
	# Web path of the CI
	ci_path=ci

	echo_bold "> Installation of YunoRunner..."
	sudo yunohost app install --force https://github.com/YunoHost-Apps/yunorunner_ynh_core -a "domain=$domain&path=/$ci_path" | $tee_to_log

	# Get the app ID of the last yunorunner installed
	app_id=$(ls /var/log/yunohost/categories/operation/*app_install*.yml | grep yunorunner | sort | tail -n1 | xargs cat | grep YNH_APP_INSTANCE_NAME | awk 'NF {last=$NF} END {print last}')

	# Stop YunoRunner
	sudo systemctl stop $app_id | $tee_to_log

	echo_bold "> Configure the path of CI_package_check..."
	sudo sed --in-place "s@/home/CI_package_check/analyseCI.sh@$script_dir/../analyseCI.sh@g" /etc/systemd/system/$app_id.service | $tee_to_log

	# Set the type of CI if needed.
	if [ "$ci_type" = "Testing_Unstable" ]
	then
		sudo sed -i "s/^ExecStart.*/& -t testing-unstable/" /etc/systemd/system/$app_id.service | $tee_to_log
	elif [ "$ci_type" = "ARM" ]
	then
		sudo sed -i "s/^ExecStart.*/& -t arm/" /etc/systemd/system/$app_id.service | $tee_to_log
	fi

	# Remove the original database, in order to rebuilt it with the new config.
	sudo rm /var/www/$app_id/db.sqlite

	# Create a random token for ciclic
	cat /dev/urandom | tr -dc _A-Za-z0-9 | head -c${1:-80} | sudo tee /var/www/$app_id/token /var/www/$app_id/tokens

	# Reboot YunoRunner to consider the configuration
	echo_bold "> Reboot YunoRunner..."
	sudo systemctl daemon-reload
	sudo systemctl restart $app_id | $tee_to_log

	# Put YunoRunner as the default app on the root of the domain
	sudo yunohost app makedefault -d "$domain" $app_id | $tee_to_log

	# Add an access to badges in the nginx config
    sudo sed -i "s@^}\$@\n\tlocation /$ci_path/badges {\n\t\talias $(dirname "$script_dir")/badges/;\n\t\tautoindex on;\n\t}\n}@" /etc/nginx/conf.d/$domain.d/$app_id.conf
	sudo systemctl reload nginx

	echo $app_id > $script_dir/../yunorunner_id
}
# SPECIFIC PART FOR YUNORUNNER (END)


SETUP_CI_APP () {
	# Setting up of a CI software as a frontend.
	# To change the software, add a new function for it and replace the following call.
# 	SETUP_JENKINS
	SETUP_YUNORUNNER
}

# Install YunoHost
echo_bold "> Check if YunoHost is already installed."
if [ ! -e /usr/bin/yunohost ]
then
	echo_bold "> YunoHost isn't yet installed."
	echo_bold "Installation of YunoHost..."
	sudo apt-get update | $tee_to_log
	sudo apt-get install -y sudo git | $tee_to_log
	git clone https://github.com/YunoHost/install_script /tmp/install_script | $tee_to_log
	cd /tmp/install_script; sudo ./install_yunohost -a | $tee_to_log

	echo_bold "> YunoHost post install"
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
echo -e "\n127.0.0.1 $domain	#CI_APP" | sudo tee -a /etc/hosts


if [ -n "$yuno_pwd" ]; then
	pass_arg="--admin-password $yuno_pwd"
else
	pass_arg=""
fi

# Check if the user already exist
if ! sudo yunohost user list --output-as json $pass_arg | grep -q "\"username\": \"$default_ci_user\""
then
	if [ -n "$yuno_pwd" ]; then
		pass_arg="--password $yuno_pwd --admin-password $yuno_pwd"
	else
		pass_arg=""
	fi
	echo_bold "> Create a YunoHost user"
	sudo yunohost user create --firstname "$default_ci_user" --mail "$default_ci_user@$domain" --lastname "$default_ci_user" "$default_ci_user" $pass_arg
fi



# Installation of the CI software, which be used as the main interface.
SETUP_CI_APP


# Build a config file
echo | sudo tee "$script_dir/auto.conf" <<EOF | $tee_to_log
# Mail pour le rapport hebdommadaire
MAIL_DEST=root


# Instance disponibles sur d'autres architectures. Un job supplémentaire sera créé pour chaque architecture indiquée.
x86-64b=0
x86-32b=0
ARM=0

# Max tests without a level (usually a crash of the CI or an app) before sending an alert.
MAX_CRASH=10

# Les informations qui suivent ne doivent pas être modifiées. Elles sont générées par le script d'installation.
# Utilisateur avec lequel s'exécute le logiciel de CI
CI=$ci_user

# Path du logiciel de CI
CI_PATH=$ci_path

# Domaine utilisé
DOMAIN=$domain

# Type de CI
CI_TYPE=$ci_type
}
EOF
echo_bold "The config file has been built in $script_dir/auto.conf"

# Installation of Package_check
echo_bold "Installation of Package check with its CI script"
"$script_dir/../build_CI.sh" | $tee_to_log

# Put lock files to prevent any usage of package check during the installation.
touch "$script_dir/../CI.lock" | $tee_to_log
touch "$script_dir/../package_check/pcheck.lock" | $tee_to_log

# Copy the default cron file
cat "$script_dir/CI_package_check_cron" >> "$script_dir/CI_package_check_cron_new"

# Move the snapshot and replace it by a symbolic link
# The symbolic link will allow to switch between Stable, Testing and Unstable container.
# We need it even for Stable only, because the CI script works with the symbolic link.
if [ "$ci_type" != "ARM" ]
then
	echo_bold "Replace the snapshot by a symbolic link"
	lxc_name=$(grep LXC_NAME= "$script_dir/../package_check/config" | cut -d '=' -f2)
	sudo mv /var/lib/lxcsnaps/$lxc_name /var/lib/lxcsnaps/pcheck_stable | $tee_to_log
	sudo ln -s /var/lib/lxcsnaps/pcheck_stable /var/lib/lxcsnaps/$lxc_name | $tee_to_log

	# Create testing and unstable containers
	# We will not create any new containers, but only duplicate the main snapshot, then modify it to create a testing and a unstable snapshot.
	# Then, to work, the CI will only change the snapshot pointed by the symbolic link.
	if [ "$ci_type" = "Mixed_content" ] || [ "$ci_type" = "Testing_Unstable" ]
	then
		for change_version in testing unstable
		do
			# Add a new directory for the snapshot
			sudo mkdir /var/lib/lxcsnaps/pcheck_$change_version | $tee_to_log

			echo_bold "> Copy the stable snapshot to create a snapshot for $change_version"
			sudo cp -a /var/lib/lxcsnaps/pcheck_stable/snap0 /var/lib/lxcsnaps/pcheck_$change_version/snap0 | $tee_to_log

			echo_bold "> Configure repositories for $change_version"
			if [ $change_version == testing ]; then
				source="testing"
			else
				source="testing unstable"
			fi
			sudo echo "deb http://forge.yunohost.org/debian/ buster stable $source" | sudo tee /var/lib/lxcsnaps/pcheck_$change_version/snap0/rootfs/etc/apt/sources.list.d/yunohost.list >> "$log_build_auto_ci" 2>&1

			# Remove lock files to allow upgrade
			sudo rm -f "$script_dir/../package_check/pcheck.lock" "$script_dir/../CI.lock" | $tee_to_log

			echo_bold "> Upgrade the container $change_version"
			sudo "$script_dir/auto_upgrade_container.sh" $change_version | $tee_to_log

			# Put back the lock files
			touch "$script_dir/../CI.lock" "$script_dir/../package_check/pcheck.lock" | $tee_to_log

			echo_bold "> Add an upgrade task in the cron for $change_version"
			if [ "$change_version" == testing ]; then
				cron_hour=4
			else
				cron_hour=5
			fi
			echo | sudo tee -a "$script_dir/CI_package_check_cron_new" <<EOF | $tee_to_log

## $change_version
# Vérifie les mises à jour du conteneur.
30 $cron_hour * * * root "$script_dir/auto_upgrade_container.sh" $change_version
EOF
			# Create a directory for the logs
			mkdir "$script_dir/../logs/logs_$change_version" | $tee_to_log
		done
		# Add another cron for triggering the upgrade of the container testing and unstable
		echo | sudo tee -a "$script_dir/CI_package_check_cron_new" <<EOF | $tee_to_log

# Trig tests in case of upgrade of containers testing and unstable
30 6 * * * root "$script_dir/testing_unstable_trigger.sh" >> "$script_dir/testing_unstable_trigger.log" 2>&1
EOF
	fi

	# Remove the stable container for a Testing_Unstable CI.
	if [ "$ci_type" = "Testing_Unstable" ]
	then
		sudo rm -r /var/lib/lxcsnaps/pcheck_stable
	fi
fi


# Change the cron to use auto_upgrade_container instead of auto_upgrade.sh
if [ "$ci_type" != "ARM" ]
then
	echo_bold "Change the cron for upgrade"
	sudo sed -i "s@package_check/sub_scripts/auto_upgrade.sh.*@auto_build/auto_upgrade_container.sh\" stable@g" "$script_dir/CI_package_check_cron_new" | $tee_to_log
fi

# Then set the path
sudo sed -i "s@__PATH__@$script_dir@g" "$script_dir/CI_package_check_cron_new" | $tee_to_log
if [ "$ci_type" = "Mixed_content" ] || [ "$ci_type" = "Stable" ]
then
	sudo sed -i "s@#Stable only#@@g" "$script_dir/CI_package_check_cron_new" | $tee_to_log
fi
if [ "$ci_type" == "ARM" ]
then
	sudo sed -i "s@#ARM only#@@g" "$script_dir/CI_package_check_cron_new" | $tee_to_log
fi

echo_bold "Set the XMPP bot"
sudo apt-get install python-xmpp | $tee_to_log
git clone https://github.com/YunoHost/weblate2xmpp "$script_dir/xmpp_bot" | $tee_to_log
sudo touch "$script_dir/xmpp_bot/password" | $tee_to_log
sudo chmod 600 "$script_dir/xmpp_bot/password" | $tee_to_log
echo "python \"$script_dir/xmpp_bot/to_room.py\" \$(sudo cat \"$script_dir/xmpp_bot/password\") \"\$@\" apps" \
	> "$script_dir/xmpp_bot/xmpp_post.sh" | $tee_to_log
sudo chmod +x "$script_dir/xmpp_bot/xmpp_post.sh" | $tee_to_log


# Remove lock files
sudo rm -f "$script_dir/../package_check/pcheck.lock" | $tee_to_log
sudo rm -f "$script_dir/../CI.lock" | $tee_to_log

# Disable list_app_ynh.sh for YunoRunner which doesn't need it.
if [ "$ci_user" == "yunorunner" ]
then
	sudo sed -i "s@.*list_app_ynh.sh.*@#&@g" "$script_dir/CI_package_check_cron_new" | $tee_to_log
else
	# Create jobs with list_app_ynh.sh
	if [ "$ci_type" != "ARM" ]
	then
		echo_bold "Create jobs"
		sudo "$script_dir/list_app_ynh.sh" | $tee_to_log
	else
		echo_bold "No build will be created now.
First, please fill the file \"$script_dir/../config\" to add at least one ARM instance.
Then, set ARM= to 1 in the config file \"$script_dir/auto.conf\"
Finally, you can run $script_dir/list_app_ynh.sh to add new jobs."
	fi
fi

# Add cron for update the app list, and to modify the level of apps.
echo_bold "Add cron tasks"
# Simply add CI_package_check_cron at the end of the current cron.
cat "$script_dir/CI_package_check_cron_new" | sudo tee -a "/etc/cron.d/$script_dir_name" > /dev/null
rm "$script_dir/CI_package_check_cron_new"
# Download the badges to put in logs
$script_dir/badges/get_badges.sh


echo_bold "Check the access rights"
if sudo su -l $ci_user -c "ls \"$script_dir\"" > /dev/null 2<&1
then
	echo -e "\e[92mAccess rights are good." | $tee_to_log
else
	echo -e "\e[91m$ci_user don't have access to the scripts !" | $tee_to_log
fi

echo ""
echo -e "\e[92mThe file $script_dir/xmpp_bot/password needs to be provided with the xmpp bot password.\e[0m" | $tee_to_log
