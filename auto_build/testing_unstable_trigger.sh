#!/bin/bash

# Get the path of this script
script_dir="$(dirname $(realpath $0))"

check_update_file () {
	if [ -e "$version_file" ]
	then
		if [ -e "$md5_file" ]
		then
			md5sum --check --status "$md5_file"
		fi
	else
		return 0
	fi
}

# Check update for testing
version_file="$script_dir/../package_check/sub_scripts/ynh_version_testing"
md5_file="$script_dir/md5_version_testing"
testing_upgrade=0
if ! check_update_file; then
	testing_upgrade=1
fi
# Update the md5 hash
md5sum "$version_file" > "$md5_file"

# Check update for unstable
version_file="$script_dir/../package_check/sub_scripts/ynh_version_unstable"
md5_file="$script_dir/md5_version_unstable"
unstable_upgrade=0
if ! check_update_file; then
	unstable_upgrade=1
fi
# Update the md5 hash
md5sum "$version_file" > "$md5_file"

start_jobs () {
	# Download the list from app.yunohost.org
	wget -nv https://app.yunohost.org/apps.json -O "$script_dir/apps.json"

        while read app
        do
                repo="${app##* \- }"
                app="${app%% \- *} ($type)"
		if [ "$list_filter" == "HQ" ]
		then
			# Get the high_quality tag for this app
			high_quality=$(jq ".$app | .high_quality" "$script_dir/apps.json")

			# Ignore the app if the tag high_quality isn't set
			if [ "$high_quality" != "true" ]
			then
				continue
			fi
		fi
                ( cd "$yunorunner_path"; ve3/bin/python ciclic add "$app" "$repo" )
        done <<< $( cd "$yunorunner_path"; ve3/bin/python ciclic app-list)
}

yunorunner_path="/var/www/yunorunner"

if [ $testing_upgrade -eq 1 ]
then
	echo "> Start tests for all apps for testing"
	type=testing
	list_filter=""
	start_jobs
fi

if [ $unstable_upgrade -eq 1 ]
then
	echo "> Start tests for all high quality apps for unstable"
	type=unstable
	list_filter="HQ"
	start_jobs
fi
