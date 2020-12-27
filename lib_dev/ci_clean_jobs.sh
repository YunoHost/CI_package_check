#!/bin/bash

#=================================================
# GET THE SCRIPT'S DIRECTORY
#=================================================

script_dir="$(dirname $(realpath $0))"

#=================================================
# DEFINE VARIABLES
#=================================================

jenkins_url=$(grep "CI_URL=" "$script_dir/config" | cut -d'=' -f2)
jenkins_java_call="sudo java -jar /var/lib/jenkins/jenkins-cli.jar -ssh -user ynhci -noCertificateCheck -s https://$jenkins_url/ -i $script_dir/jenkins/jenkins_key"

ssh_chroot_directory="/home/yunohost.app/ssh_chroot_directories"

#=================================================
# PRINT THE CURRENTS JENKINS JOBS
#=================================================

$jenkins_java_call list-jobs > "$ssh_chroot_directory/job_list"

#=================================================
# REMOVE THE JOBS FOR OLD APPS
#=================================================

while read app
do
	# Get the directory for this job in the list
	directory="$(grep -m1 "$app" "$ssh_chroot_directory/list_job_dir" | cut -d':' -f2)"
	# If there no file newer than 180 days (6 months), remove this app.
	if [ $(find "$directory" -type f -mtime -180 ! -path "*.git*" | wc --lines) -eq 0 ]
	then
		echo "Remove the old app $app"
		sudo rm -r "$directory"
	fi
done < "$ssh_chroot_directory/job_list"

#=================================================
# REMOVE THE JOBS FOR APPS WHICH DOESN'T EXIST
#=================================================

while read <&3 app
do
	# Get the directory for this job in the list
	directory="$(grep -m1 "$app" "$ssh_chroot_directory/list_job_dir" | cut -d':' -f2)"
	# If the directory doesn't exist anymore, remove this job
	if [ ! -d "$directory" ]
	then
		echo "Remove the job $app"
		$jenkins_java_call delete-job "$app"
		# And remove the job in the list
		sed --in-place "/^$app:/d" "$ssh_chroot_directory/list_job_dir"
	fi
done 3< "$ssh_chroot_directory/job_list"

#=================================================
# UPDATE THE LIST OF CURRENT DIRECTORIES
#=================================================

sudo find "$ssh_chroot_directory" -type d -name '*_ynh' > "$ssh_chroot_directory/current"

# Caculate the checksum of the list of apps
md5sum "$ssh_chroot_directory/current" > "$ssh_chroot_directory/current.md5"
