#!/bin/bash

#=================================================
# Grab the script directory
#=================================================

if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

#=================================================
# Check if Package check is already used
#=================================================

if test -e "$script_dir/../package_check/pcheck.lock"
then
	echo "The file $script_dir/../package_check/pcheck.lock exist. Package check is already used. Switch container cancelled..."
	exit 1
fi

#=================================================
# Get variables
#=================================================

# Name of the container
lxc_name=$(grep LXC_NAME= "$script_dir/../package_check/config" | cut --delimiter='=' --fields=2)
# Type of test, stable, testing or unstable
type=$1

#=================================================
# Switch the snapshot
#=================================================

# If the main snapshot is a symbolic link, it's the official CI instance
if [ -h /var/lib/lxcsnaps/$lxc_name ]
then
	# Check if the symbolic link is already good.
	if ! sudo ls -l /var/lib/lxcsnaps/pchecker_lxc | grep --quiet "_$type"
	then
		echo "> Changement de conteneur vers $type"
		# Remove the previous symbolic link
		sudo rm /var/lib/lxcsnaps/$lxc_name
		# And recreate it with a another linked snapshot
		sudo ln --symbolic --force /var/lib/lxcsnaps/pcheck_$type /var/lib/lxcsnaps/$lxc_name
	fi
fi
