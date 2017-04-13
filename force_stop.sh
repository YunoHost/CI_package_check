#!/bin/bash

if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

lock_pcheckCI="$script_dir/CI.lock"

# Get the id of the current test
id=$(cat "$lock_pcheckCI")

# Inform analyseCI.sh that the test was finish
echo Finish > "$lock_pcheckCI"

# Remove this test of the work_list
sudo sed --in-place "/$id/d" "$script_dir/work_list"

# Kill package_check
# Retrieve the pid of Package check
get_pid="ps -C package_check.sh -o pid="

# Loop while package_check is still running
while $get_pid > /dev/null
do
	sudo kill --signal 15 $($get_pid | head --line=1)
done

# Stop the container and its network
sudo "$script_dir/package_check/sub_scripts/lxc_force_stop.sh"

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
sudo rm "$script_dir/package_check/pcheck.lock"
sudo rm "$lock_pcheckCI"
