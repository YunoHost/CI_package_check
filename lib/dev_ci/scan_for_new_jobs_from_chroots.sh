#!/bin/bash

ssh_chroot_directory="/home/yunohost.app/ssh_chroot_directories"

# This is where we'll put app folder to be picked up by the CI
mkdir -p /home/dev_ci_app_folders/

# Cleanup old job folders (older than 2 days)
find /home/dev_ci_app_folders/* -type d -ctime +2 -exec rm -rf {} \;

#=================================================
# CREATE A JOB FOR EACH NEW APP IN THE CHROOT DIRS
#=================================================
for app_folder_in_chroot_dir in $(find "$ssh_chroot_directory" -type d -name '*_ynh*')
do
     # app_folder_in_chroot_dir is something like:
     # /home/yunohost.app/ssh_chroot_directories/aleks/data/helloworld_ynh
     app_name="$(basename "$app_folder_in_chroot_dir")"
     user_name=$(basename $(dirname $(dirname "$app_folder_in_chroot_dir")))
     app_folder_for_job=$(mktemp -u -d "/home/dev_ci_app_folders/${app_name}_${user_name}.XXXXXXX")
     
     # Keep only the PR number for Official jobs
     if echo "$app_name" | grep --quiet -E ".*_ynh PR[[:digit:]]*\."
     then
         job_name="$(echo "$app_name" | sed 's/\(.*_ynh PR[[:digit:]]*\)..*/\1/')"
     else
         job_name="$app_name ($user_name)"
     fi
     
     echo "Add a new job for $job_name"
     mv "${app_folder_in_chroot_dir}" "${app_folder_for_job}"
     # Gotta be in the same directory because of the token stuff idk
     cd /var/www/yunorunner
     ve3/bin/python ciclic add "$job_name" "$app_folder_for_job"
done
