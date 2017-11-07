#!/bin/bash

#=================================================
# GET THE SCRIPT'S DIRECTORY
#=================================================

script_dir="$(dirname $(realpath $0))"

#=================================================
# DEFINE VARIABLES
#=================================================

ci_path=$(grep "CI_PATH=" "$script_dir/config.conf" | cut -d'=' -f2)
domain=$(grep "DOMAIN=" "$script_dir/config.conf" | cut -d'=' -f2)
jenkins_url=$domain/$ci_path
jenkins_java_call="sudo java -jar /var/lib/jenkins/jenkins-cli.jar -remoting -noCertificateCheck -s https://$jenkins_url/ -i $script_dir/jenkins/jenkins_key"
base_jenkins_job="$script_dir/jenkins/jenkins_job"

ssh_chroot_directory="/home/yunohost.app/ssh_chroot_directories"

#=================================================
# SCAN THE CURRENTS APP DIRECTORIES
#=================================================

sudo find "$ssh_chroot_directory" -type d -name '*_ynh' > "$ssh_chroot_directory/current"

# Continue only if there a modification into the list of apps.
if ! md5sum --check --status "$ssh_chroot_directory/current.md5"
then
	# Caculate the checksum of the list of apps
	md5sum "$ssh_chroot_directory/current" > "$ssh_chroot_directory/current.md5"

	#=================================================
	# PRINT THE CURRENTS JENKINS JOBS
	#=================================================

	$jenkins_java_call list-jobs > "$ssh_chroot_directory/job_list"

	#=================================================
	# CREATE A JOB FOR EACH NEW APP
	#=================================================

	while read app
	do
		# Get only the name of the app
		app_name=$(basename "$app")
		#˘Remove the directory at the beginning
		user_name="${app//$ssh_chroot_directory/}"
		# Then remove all the directory after the user name
		user_name="${user_name//data*/}"
		# And remove the first and the last slash
		user_name="${user_name:1:$((${#user_name}-2))}"
		# Build the name of the job
		job_name="$app_name ($user_name)"

		# Check if this job exist in the job_list
		if ! grep --quiet "$job_name" "$ssh_chroot_directory/job_list"
		then
			echo "Add a new job for $job_name"
			# If the job doesn't exist yet, add it
			# First configure the job
			cp "${base_jenkins_job}.xml" "${base_jenkins_job}_load.xml"
			sed --in-place "s@__PATH__@$(dirname "$script_dir")@g" "${base_jenkins_job}_load.xml"
					sed --in-place "s@__APP_DIR__@$app@g" "${base_jenkins_job}_load.xml"
			# Then create the job
			$jenkins_java_call create-job "$job_name" < "${base_jenkins_job}_load.xml"
			# And add this job to the list
			echo "$job_name:$app" >> "$ssh_chroot_directory/list_job_dir"

			$jenkins_java_call build "$job_name"

		fi
	done < "$ssh_chroot_directory/current"
fi
