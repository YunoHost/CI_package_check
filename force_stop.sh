#!/bin/bash

if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

lock_pcheckCI="$script_dir/CI.lock"

# Remove the ssh marker
rm -f "$script_dir/ssh_running"

# Get the id of the current test
id=$(head -n1 "$lock_pcheckCI")

# Inform analyseCI.sh that the test was finish
echo Finish > "$lock_pcheckCI"

# Remove this test of the work_list
sudo sed --in-place "/$id/d" "$script_dir/work_list"

# Stop package_check, the container and its network
#source "$script_dir/package_check/lib/common.sh"
# FIXME ... fetch the LXC_NAME and run `lxc stop $LXC_NAME --timeout 15` or
# something similar..

# Wait for the cleaning of the lock file. That means analyseCI.sh finished on its side.
starttime=$(date +%s)

while test -s "$lock_pcheckCI"
do
	# Check the timeout
	if [ $(( $(date +%s) - $starttime )) -ge 120 ]; then
		break
	fi
	sleep 1
done

# Remove the lock files
sudo rm "$lock_pcheckCI"
