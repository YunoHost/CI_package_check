#!/bin/bash

# This script is designed to be used in a cron file

#=================================================
# Grab the script directory
#=================================================

if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

echo ""
date

#=================================================
# Check the lock file before continuing
#=================================================

lock_pcheckCI="$script_dir/CI.lock"

if test -e "$lock_pcheckCI"
then
	echo "The file $(basename "$lock_pcheckCI") exist. Another test is already in progress."
	echo "Postpone this upgrade to 30min later..."

	# Postpone this script 30 minutes later
	echo "\"$script_dir/auto_upgrade.sh\" >> \"$script_dir/auto_upgrade.log\" 2>&1" | at now + 30 min

	exit 0
fi

# Set a lock file for this upgrade
echo "Upgrade" > "$lock_pcheckCI"

#=================================================
# Upgrade CI_package_check
#=================================================

git_repository=https://github.com/YunoHost/CI_package_check
version_file="$script_dir/ci_pcheck_version"

check_version="$(git ls-remote $git_repository | cut -f 1 | head -n1)"

# If the version file exist, check for an upgrade
if [ -e "$version_file" ]
then
	# Check if the last commit on the repository match with the current version
	if [ "$check_version" != "$(cat "$version_file")" ]
	then
		# If the versions don't matches. Do an upgrade
		echo -e "Upgrade CI_package_check...\n"

		# Build the upgrade script
		cat > "$script_dir/upgrade_script.sh" << EOF

#!/bin/bash
# Clone in another directory
git clone --quiet $git_repository "$script_dir/upgrade"
cp -a "$script_dir/upgrade/." "$script_dir/."
rm -r "$script_dir/upgrade"
# Update the version file
echo "$check_version" > "$version_file"
# Remove the lock file
rm "$lock_pcheckCI"
EOF

		# Give the execution right
		chmod +x "$script_dir/upgrade_script.sh"

		# Start the upgrade script by replacement of this process
		exec "$script_dir/upgrade_script.sh"
	fi
fi

# Update the version file
echo "$check_version" > "$version_file"

# Remove the lock file
rm "$lock_pcheckCI"
