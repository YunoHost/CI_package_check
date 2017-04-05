#!/bin/bash

# This script will be executed by the CI software (Usually Jenkins)
# This script CAN'T have any root access.
# All information print on stdout will be printed by the CI software.

#=================================================
# Grab the script directory
#=================================================

if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

#=================================================
# Check the number of arguments
#=================================================

if [ $# -ne 2 ]
then
	echo "This script need to take in argument the package which be tested and the name of the test."
	exit 1
fi

# Repository
repo="$1"
# Test name
test_name="$2"

#=================================================
# Delay the beginning of this script, to prevent concurrent executions
#=================================================

# Get 3 ramdom digit. To build a value between 001 and 999
milli_sleep=$(head --lines=20 /dev/urandom | tr --complement --delete '0-9' | head --bytes=3)
# And wait for this value in millisecond
sleep "0.$milli_sleep"

#=================================================
# Define a unique ID for this test
#=================================================

id=$(head --lines=20 /dev/urandom | tr --complement --delete 'A-Za-z0-9' | head --bytes=10)

#=================================================
# Add a test to the work_list
#=================================================

echo "$repo;$id;$test_name" >> "$script_dir/work_list"

# This file will be read by pcheckCI.sh
# And pcheckCI.sh will launch a test by using the informations in this line.

#=================================================
# Execution indicator
#=================================================

# Update a indicator file periodically to prove that the script doesn't stopping his execution
exec_indicator () {
	# Loop as long as the file exist
	while test -e "$script_dir/analyseCI_last_exec"
	do
		# Update the file with the current time and the id.
		echo "$(date +%s);$id" > "$script_dir/analyseCI_last_exec"
		# Wait 2 minutes and redo
		sleep 120
	done
}
# Start the indicator loop in background.
exec_indicator &

#=================================================
# Time out
#=================================================

set_timeout () {
	# Get the maximum timeout value + 10 minutes
	timeout=$(( $(grep "timeout=" "$script_dir/config" | cut --delimiter="=" --fields=2) + 600 ))

	# Set the starting time
	starttime=$(date +%s)
}

# Check if the timeout has expired
timeout_expired () {
	# Compare the current time with the max timeout
	if [ $(( $(date +%s) - $starttime )) -ge $timeout ]
	then
		echo -e "\e[91m\e[1m!!! Execution aborted, timeout reached ($(( $timeout / 60 )) min). !!!\e[0m"
		exit 1
	fi
}

#=================================================
# Wait for the beginning of the script pcheckCI
#=================================================

echo ""
# Simply print the date, for information
date
echo "Wait for work starting..."

# Start the time counter
set_timeout

# Start a infinite loop
while true
do
	# Check the lock file. Indicator of pcheckCI execution
	if test -e "$script_dir/CI.lock"
	then
		# Check if the lock file contains the id of the current test
		if [ "$(cat "$script_dir/CI.lock")" = "$id" ]
		then
			# If the lock file contains the current id, the test has begun. Break the waiting loop
			break
		fi
	fi
	# Check the timeout, another way to break this loop.
	timeout_expired

	sleep 30
	echo -n "."
done

#=================================================
# Follow the testing process
#=================================================

echo ""
# Simply print the date, for a progress information
date
echo "Package check currently test the package"

log_line=0
log_cli="$script_dir/package_check/Test_results_cli.log"

# Restart the time counter
set_timeout

# Loop as long as the lock file doesn't contain "Finish" indication
while [ "$(cat "$script_dir/CI.lock")" != "Finish" ]
do
	# Check the timeout
	timeout_expired

	# Print the progression of the test every 10 seconds
	sleep 10

	# If $log_line equal 0, it's the first pass.
	if [ $log_line -eq 0 ]
	then
		# Simply print the current log.
		cat "$log_cli"

	# Or print the log from the last readed line
	else
		tail --lines=+$(( $log_line + 1 )) "$log_cli"
	fi

	# Count the number of lines previously read
	log_line=$(wc --lines "$log_cli" | cut --delimiter=' ' --fields=1)
done
echo ""
date
echo "Test finished."

#=================================================
# Clean the lock file
#=================================================

# Clean the log file for inform pcheckCI that this script is finished.
echo -n "" > "$script_dir/CI.lock"

#=================================================
# Check the final results
#=================================================

# Success by default
result=0

# Search for some FAIL in the final results
# But, ignore the line of package linter.
if grep "FAIL$" "$log_cli" | grep -v "Package linter" | grep -q "FAIL$"
then
	# If a fail was find, the test failed.
	result=1

# Search also for a "PCHECK_AVORTED". That means the script pcheckCI was aborted by a timeout.
elif grep "PCHECK_AVORTED" "$log_cli"
then
	result=1

# And, finally, check if at least one test was a success.
elif ! grep "SUCCESS$" "$log_cli" | grep -v "Package linter" | grep -q "SUCCESS$"
then
	result=1
fi

# Exit with the result as exit code. To inform the CI software of the global result
exit $result


# On indiquera "Finish" dans le lock file pour dire qu'on a terminé.

# analyseCI_last_exec a besoin d'un 666
# Et doit donc être créé à part... Par pcheckCI
