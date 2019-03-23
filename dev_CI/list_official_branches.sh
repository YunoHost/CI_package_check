#!/bin/bash

# List all apps from official

github_user=
github_token=

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
# LIST ALL PULL REQUESTS FOR EACH OFFICIAL APPS
#=================================================

while read app
do
        appname="$(basename $app)_ynh"

        # Purge the list of branches
        > "$app/branches"

        # List all Pull Request
        # Get the json with all Pull request from github API.
        curl -u $github_user:$github_token --silent --show-error https://api.github.com/repos/YunoHost-Apps/${appname}/pulls?state=open > "$script_dir/PR_extract.json"

        max_PR=$(jq length "$script_dir/PR_extract.json")
        for i in $(seq 0 $(( $max_PR - 1)) )
        do
            # Get the ID of this pull request
            echo -n "$(jq --raw-output ".[$i] | .number" "$script_dir/PR_extract.json")  " >> "$app/branches"
            # Get the repo for this pull request
            echo -n "$(jq --raw-output ".[$i] | .head.repo.clone_url" "$script_dir/PR_extract.json")  " >> "$app/branches"
            # Get the branch for this pull request
            echo "$(jq --raw-output ".[$i] | .head.ref" "$script_dir/PR_extract.json")" >> "$app/branches"
        done
done < "$current_jobs"

#=================================================
# REMOVE DELETED BRANCHES
#=================================================

while read app
do
	# For each app, check each branches.
	appname="$(basename $app)_ynh"
	while <&4 read branch_dir
	do
		if [ -n "$branch_dir" ]
		then
			branch="${branch_dir##*_ynh *[[:digit:]].}"
			# If the branch isn't in the branches files. Remove it
			if ! grep --quiet --extended-regexp " $branch$" "$app/branches"
			then
				echo "Remove the branch $branch for the app $appname"
				sudo rm -r "$branch_dir"
			fi
		fi
	done 4<<< "$(sudo find "$app" -maxdepth 1 -type d | tail -n+2)"
done < "$current_jobs"

#=================================================
# UPDATE ALL BRANCHES AND ADD NEW ONES
#=================================================

while read app
do
	# For each app, check each branches.
	appname="$(basename $app)_ynh"
	while <&4 read branch
	do
		pr_id="$(echo "$branch" | awk '{print $1}')"
		pr_repo="$(echo "$branch" | awk '{print $2}')"
		pr_branch="$(echo "$branch" | awk '{print $3}')"

		branch_directory="$app/$appname PR$pr_id.$pr_branch"
		# If this branch already exist, update
		if [ -e "$branch_directory" ]
		then
			echo "Update the branch $pr_branch, PR$pr_id for the app $appname"
			(cd "$branch_directory"
			git pull)
			# If git return 1
			if [ $? -eq 1 ]
			then
				# Return code 1 is 'No such ref was fetched', so the branch doesn't exist anymore.
				echo "Remove the branch $pr_branch, PR$pr_id for the app $appname"
				sudo rm -r "$branch_directory"
			fi

		# Otherwise, create a new directory for this branch
		else
			echo "Add the new branch $pr_branch, PR$pr_id for the app $appname"
			git clone --quiet $pr_repo "$branch_directory" > /dev/null
			(cd "$branch_directory"
			git checkout "$pr_branch" > /dev/null)
		fi
	done 4< "$app/branches"
done < "$current_jobs"
