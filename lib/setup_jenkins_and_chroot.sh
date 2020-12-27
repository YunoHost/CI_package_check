#!/bin/bash

# User which execute the CI software.
ci_user=jenkins
# Web path of the CI
ci_path=ci

echo_bold "> Installation of jenkins..."
yunohost app install --force https://github.com/YunoHost-Apps/jenkins_ynh -a "domain=$domain&path=/$ci_path&is_public=1"

# Keep 1 simultaneous test only
sed -i "s/<numExecutors>.*</<numExecutors>1</" /var/lib/jenkins/config.xml

# Set up an ssh connection for jenkins cli.
# Create a new ssh key.
echo_bold "> Create a ssh key for jenkins-cli."
ssh-keygen -t rsa -b 4096 -N "" -f "./lib/jenkins/jenkins_key" > /dev/null
chown root: "./lib/jenkins/jenkins_key"
chmod 600 "./lib/jenkins/jenkins_key"

# Configure jenkins to use this ssh key.
echo_bold "> Create a basic configuration for jenkins' user."
# Create a directory for this user.
mkdir -p "/var/lib/jenkins/users/$default_ci_user"
# Copy the model of config.
cp "./lib/jenkins/user_config.xml" "/var/lib/jenkins/users/$default_ci_user/config.xml"
# Add a name for this user.
sed -i "s/__USER__/$default_ci_user/g" "/var/lib/jenkins/users/$default_ci_user/config.xml"
# Add the ssh key
sed -i "s|__SSH_KEY__|$(cat "./lib/jenkins/jenkins_key.pub")|"  "/var/lib/jenkins/users/$default_ci_user/config.xml"
chown jenkins: -R "/var/lib/jenkins/users"
# Configure ssh port in jenkins config
echo | tee "/var/lib/jenkins/org.jenkinsci.main.modules.sshd.SSHD.xml" <<EOF
<?xml version='1.0' encoding='UTF-8'?>
<org.jenkinsci.main.modules.sshd.SSHD>
<port>0</port>
</org.jenkinsci.main.modules.sshd.SSHD>
EOF
chown jenkins: "/var/lib/jenkins/org.jenkinsci.main.modules.sshd.SSHD.xml"

# Copy AnsiColor configuration
cp "./lib/jenkins/hudson.plugins.ansicolor.AnsiColorBuildWrapper.xml" /var/lib/jenkins/

# Reboot jenkins to consider the new key
echo_bold "> Reboot jenkins to handle the new ssh key..."
systemctl restart jenkins 

tempfile="$(mktemp)"
tail -f -n1 /var/log/jenkins/jenkins.log > "$tempfile" &	# Follow the boot of jenkins in its log
pid_tail=$!	# get the PID of tail
timeout=3600
for i in `seq 1 $timeout`
do	# Because it can be really long on a ARM architecture, wait until $timeout or the boot of jenkins.
    if grep -q "Jenkins is fully up and running" "$tempfile"; then
        echo "Jenkins has started correctly."
        break
    fi
    sleep 1
done
kill -s 15 $pid_tail > /dev/null	# Stop tail
rm "$tempfile"
if [ "$i" -ge $timeout ]; then
    echo "Jenkins hasn't started before the timeout (${timeout}s)."
fi

# Put jenkins as the default app on the root of the domain
yunohost app makedefault -d "$domain" jenkins


# Modifie la config nginx pour ajouter l'accès aux logs
mv "/etc/nginx/conf.d/$domain.d/$ci_path.conf" "/etc/nginx/conf.d/$domain.d/$ci_path.conf_copy"
echo | tee "/etc/nginx/conf.d/$domain.d/$ci_path.conf" <<EOF
location /$ci_path/logs {
   alias /home/CI_package_check/logs/;
   autoindex on;
}

EOF
cat "/etc/nginx/conf.d/$domain.d/$ci_path.conf_copy" >> "/etc/nginx/conf.d/$domain.d/$ci_path.conf"
rm "/etc/nginx/conf.d/$domain.d/$ci_path.conf_copy"
systemctl reload nginx


# Installation de ssh_chroot_dir
yunohost app install --force https://github.com/YunoHost-Apps/ssh_chroot_dir_ynh -a "ssh_user=base_user&password=""&pub_key=fake_key&size=1G"

# Créer un lien symbolique pour un accès facile à chroot_manager
ln -sf /home/yunohost.app/ssh_chroot_directories/chroot_manager ./chroot_manager
# Et à l'ajout d'utilisateur.
ln -sf "lib_dev/Add_a_new_user.sh" ./Add_a_new_user.sh
