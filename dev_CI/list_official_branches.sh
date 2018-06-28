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
none_official_directory="/home/yunohost.app/ssh_chroot_directories/Official_fork/data"
ynh_list="$jobs_directory/ynh_list"
current_jobs="$jobs_directory/current_jobs"

#=================================================
# BUILD LIST OF CURRENT APPS
#=================================================

sudo find "$jobs_directory" -maxdepth 1 -type d | tail -n+2 > "$current_jobs"

#=================================================
# LIST ALL BRANCHES FOR EACH OFFICIAL APPS
#=================================================

while read app
do
	appname="$(basename $app)_ynh"
	# List all branches
	(cd "$app/$appname testing"
	git branch --remotes > "$app/branches")

	# Then clean the list
	sed -i '\|origin/HEAD*|d' "$app/branches"
	sed -i '\|origin/master*|d' "$app/branches"
	sed -i 's|  origin/||' "$app/branches"
done < "$current_jobs"

#=================================================
# REMOVE DELETED BRANCHES
#=================================================

while read app
do
	# For each app, check each branches.
	appname="$(basename $app)_ynh"
	while <&4 read branch
	do
		branch="${branch##*_ynh }"
		# If the branch isn't in the branches files. Remove it
		if ! grep --quiet "$branch" "$app/branches"
		then
			echo "Remove the branch $branch for the app $appname"
			sudo rm -r "$app/$appname $branch"
		fi
	done 4<<< "$(sudo find "$app" -maxdepth 1 -type d | tail -n+2)"
done < "$current_jobs"

#=================================================
# UPDATE ALL BRANCHES
#=================================================

while read app
do
	# For each app, check each branches.
	appname="$(basename $app)_ynh"
	while <&4 read branch
	do
		branch_directory="$app/$appname $branch"
		# If this branch already exist, update
		if [ -e "$branch_directory" ]
		then
			echo "Update the branch $branch for the app $appname"
			(cd "$branch_directory"
			git pull)
                        # If git return 1
                        if [ $? -eq 1 ]
                        then
                                # Return code 1 is 'No such ref was fetched', so the branch doesn't exist anymore.
                                echo "Remove the branch $branch for the app $appname"
                                sudo rm -r "$app/$appname $branch"
                        fi

		# Otherwise, create a new directory for this branch
		else
			# Get the repository for this app
			repo=$(grep "$appname" "$ynh_list" | cut -d';' -f1)

			echo "Add the new branch $branch for the app $appname"
			git clone --quiet $repo "$branch_directory" > /dev/null
			(cd "$branch_directory"
			git checkout "$branch" > /dev/null)
		fi
	done 4< "$app/branches"
done < "$current_jobs"

#=================================================

#=================================================
# BUILD LIST OF OFFICIAL FORKS
#=================================================

sudo find "$none_official_directory" -maxdepth 1 -type d | tail -n+2 > "$current_jobs"

#=================================================
# UPDATE ALL BRANCHES
#=================================================

while read app
do
        # For each forked repository, update the code
        echo "Update the official fork $app"
        (cd "$app"
        git pull -a)
done < "$current_jobs"
