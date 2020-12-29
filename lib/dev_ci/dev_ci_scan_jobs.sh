#!/bin/bash

#=================================================
# GET THE SCRIPT'S DIRECTORY
#=================================================

script_dir="$(dirname $(realpath $0))"

#=================================================
# SCAN THE CURRENTS APP DIRECTORIES
#=================================================

ciclic="/var/www/yunorunner/ve3/bin/python /var/www/yunorunner/ciclic"

ssh_chroot_directory="/home/yunohost.app/ssh_chroot_directories"
find "$ssh_chroot_directory" -type d -name '*_ynh*' > "$ssh_chroot_directory/current"

# Continue only if there a modification into the list of apps.
if ! md5sum --check --status "$ssh_chroot_directory/current.md5"
then
	#=================================================
	# PRINT THE CURRENTS JOBS
	#=================================================

	$ciclic list | grep "\[scheduled\]" > "$ssh_chroot_directory/job_list"

	#=================================================
	# CREATE A JOB FOR EACH NEW APP
	#=================================================

	while read <&3 app
	do
		# Get only the name of the app
		app_name=$(basename "$app")
		#˘Remove the directory at the beginning
		user_name="${app//$ssh_chroot_directory/}"
		# Then remove all the directory after the user name
		user_name="${user_name//data*/}"
		# And remove the first and the last slash
		user_name="${user_name:1:$((${#user_name}-2))}"
		# Keep only the PR number for Official jobs
		if echo "$app_name" | grep --quiet -E ".*_ynh PR[[:digit:]]*\."
		then
			job_name="$(echo "$app_name" | sed 's/\(.*_ynh PR[[:digit:]]*\)..*/\1/')"
		else
			# Build the name of the job
			job_name="$app_name ($user_name)"
		fi

		# Check if this job exist in the job_list
		if grep --quiet "$job_name" "$ssh_chroot_directory/job_list"
		then
            continue
        fi

        echo "Add a new job for $job_name"
        $ciclic add "$job_name" "$app"

	done 3< "$ssh_chroot_directory/current"

	# Caculate the checksum of the list of apps
	md5sum "$ssh_chroot_directory/current" > "$ssh_chroot_directory/current.md5"
fi
