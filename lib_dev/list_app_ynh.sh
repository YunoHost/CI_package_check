#!/bin/bash

# List all apps from official

#=================================================
# Grab the script directory
#=================================================

script_dir="$(dirname $(realpath $0))"

#=================================================
# Define variables
#=================================================

jobs_directory="/home/yunohost.app/ssh_chroot_directories/Official/data"
mkdir -p "$jobs_directory"
ynh_list="$jobs_directory/ynh_list"
current_jobs="$jobs_directory/current_jobs"

#=================================================
# BUILD LIST OF CURRENT APPS
#=================================================

sudo find "$jobs_directory" -maxdepth 1 -type d | tail -n+2 | sed "s@$jobs_directory/@@" > "$current_jobs"

#=================================================
# LIST HIGH QUALITY APPS
#=================================================

# Download the list from app.yunohost.org
wget -nv https://app.yunohost.org/apps.json -O "$jobs_directory/apps.json"

# Purge the list
> "$ynh_list"

# Parse each git repository
while read appname
do
	# Get the high_quality tag for this app
	high_quality=$(jq ".$appname | .high_quality" "$jobs_directory/apps.json")

	# Add the app to the list only if the tag high_quality is set
	if [ "$high_quality" == "true" ]
	then
		# Get the repo for this app
		repo=$(jq --raw-output ".$appname | .git.url" "$jobs_directory/apps.json")

		# Print the repo and the name of the job into the list
		echo "$repo;${appname}" >> "$ynh_list"
	fi
# List all apps from the list, by getting manifest ID.
done <<< "$(jq --raw-output ".[] | .manifest.id" "$jobs_directory/apps.json")"

#=================================================
# REMOVE OLD APPS
#=================================================

# Check each app in the list of current jobs
while read app
do
	# Check if this app can be found in the yunohost list
	if ! grep --quiet "$app" "$ynh_list"
	then
		echo "Remove the application $app"
		if [ -n "$app" ] # Just in case of nasty rm ;)
		then
			sudo rm -r "$jobs_directory/$app"
		fi
	fi
done < "$current_jobs"

#=================================================
# ADD NEW APPS
#=================================================

# Check each app in the list of current jobs
while read app
do
	# Get the name of this app
	appname=$(echo "$app" | cut --delimiter=';' --fields=2)
	# Check if this app can be found in the list of current jobs
	if ! grep --quiet "^$appname$" "$current_jobs"
	then
		# Get the repository
		repo=$(echo "$app" | cut --delimiter=';' --fields=1)

		echo "Add the application $appname for the repository $repo"
		mkdir "$jobs_directory/$appname"
		git clone --quiet $repo "$jobs_directory/$appname/${appname}_ynh testing" > /dev/null
		(cd "$jobs_directory/$appname/${appname}_ynh testing"
		git checkout testing > /dev/null)
	fi
done < "$ynh_list"
