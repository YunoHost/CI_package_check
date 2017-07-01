#!/bin/bash

#=================================================
# Grab the script directory
#=================================================

if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

#=================================================
# Time out
#=================================================

set_timeout () {
	# Get the maximum timeout value
	timeout=$(grep "^timeout=" "$script_dir/config" | cut --delimiter="=" --fields=2)

	# Set the starting time
	starttime=$(date +%s)
}

# Check if the timeout has expired
timeout_expired () {
	# Compare the current time with the max timeout
	if [ $(( $(date +%s) - $starttime )) -ge $timeout ]
	then
		echo -e "\e[91m\e[1m!!! Timeout reached ($(( $timeout / 60 )) min). !!!\e[0m"
		return 1
	fi
}

#=================================================
# Check analyseCI execution
#=================================================

# Check if the analyseCI is still running
check_analyseCI () {

	sleep 120

	# Get the pid of analyseCI
	local analyseCI_pid=$(cat "$analyseCI_indic" | cut --delimiter=';' --fields=1)
	local analyseCI_id=$(cat "$analyseCI_indic" | cut --delimiter=';' --fields=2)
	local finish=0


	# Infinite loop
	while true
	do

		# Check if analyseCI still running by its pid
		if ! ps --pid $analyseCI_pid | grep --quiet $analyseCI_pid
		then
			echo "analyseCI stopped."
			# Check if the lock file contains "Remove". That means analyseCI has finish normally
			[ "$(cat "$lock_pcheckCI")" == "Remove" ] && finish=1
			break
		fi

		# Check if analyseCI wait for the correct id.
		if [ "$analyseCI_id" != "$id" ]
		then
			echo "analyseCI wait for another id."
			finish=2

			break
		fi

		# Wait 30 secondes and recheck
		sleep 30
	done

	# if finish equal 0, analyseCI was aborted, in this case, kill all current process.
	if [ $finish -eq 0 ]
	then
		echo -e "\e[91m\e[1m!!! analyseCI was cancelled, stop this test !!!\e[0m"
		# Stop all current tests
		"$script_dir/force_stop.sh"
		echo ""

	# If finish equal 1, analyseCI finished correctly. It's the normal way to ending this script. So remove the lock file
	elif [ $finish -eq 1 ]
	then
		# Remove the lock file
		rm -f "$lock_pcheckCI"
		date
		echo -e "Lock released for $test_name (id: $id)\n"

	# Else, finish equal 2, analyseCI is waiting for another test (another id)
	else
		# Remove this test from the work_list
		grep --quiet "$id" "$work_list" & sed --in-place "/$id/d" "$work_list"
	fi
}

#=================================================
# Start a test through SSH
#=================================================

PCHECK_SSH () {
	echo "Start a test on $ssh_host for $architecture architecture"
	echo "Initialize an ssh connection"

	# Make a call to analyseCI.sh through ssh
	ssh $ssh_user@$ssh_host -p $ssh_port -i $ssh_key \
		"\"$pcheckci_path/analyseCI.sh\" \"$repo\" \"$test_name\""

	# Copy the complete log from the distant machine
	scp -P $ssh_port -i $ssh_key \
		$ssh_user@$ssh_host:"$pcheckci_path/package_check/Complete.log" \
		"$script_dir/logs/$complete_app_log"
}

#=================================================
# Start a test with the local instance of package check
#=================================================

PCHECK_LOCAL () {
	echo -n "Start a test"
	if [ -n "$architecture" ]; then
		echo " for $architecture architecture"
	fi

	# Start package check and pass to background
	"$script_dir/package_check/package_check.sh" --bash-mode "$repo" &


	# Get the pid of package check
	package_check_pid=$!

	# Start the time counter
	set_timeout

	# Start a loop while package check is working
	while ps --pid $package_check_pid | grep --quiet $package_check_pid
	do

		# Check if the timeout is not expired
		if ! timeout_expired
		then
			echo -e "\e[91m\e[1m!!! Package check was too long, its execution was aborted. !!! (PCHECK_AVORTED)\e[0m" | tee --append "$cli_log"

			# Stop all current tests
			"$script_dir/force_stop.sh" &
			exit 1
		fi
		sleep 30
	done

	# Copy the complete log
	cp "$script_dir/package_check/Complete.log" "$script_dir/logs/$complete_app_log"
}

#=================================================
# Exec package check according to the architecture
#=================================================

EXEC_PCHECK () {
	# Sort of load balancing to choose which instance will be used.
	choose_a_instance () {
		# As argument, take the list of all instance, one per line.
		local list_instance="$@"

		# Create an array to store the informations about each instance
		local -a instances='()'
		local max_weight=0
		# Read each line of the argument, means each instance.
		while read local line
		do
			# Remove '> ' at the beginning
			line=${line#> }
			# Keep only the number of this instance, like a id
			local num="${line%%.*}"
			# Grab the weight of this instance
			local weight="${line##*=}"
			# Add up the weights of each instance to have a total weight
			max_weight=$(( max_weight + weight ))
			# Add a new field to the array.
			instances+=($num:$max_weight)
		done <<< "$list_instance"

		local max_instance=${#instances[@]}
		# Find a random value between 1 and max_weight
		local find_instance=$(( ( RANDOM % $max_weight ) +1 ))

		# With this random value, find the associate instance, depending of the weight of each one.
		for i in `seq 0 $(( max_instance - 1))`
		do
			weight=$(echo ${instances[$i]} | cut -d: -f2)

			if [ $find_instance -le $weight ]; then
				# Return the number of this instance (Its ID)
				echo $(echo ${instances[$i]} | cut -d: -f1)
				return 0
			fi
		done
	}

	# Check the asked architecture
	# And define a prefix to get the infos in the config file.
	if [ "$architecture" = "~x86-64b~" ]
	then
		arch_pre=64
	elif [ "$architecture" = "~x86-32b~" ]
	then
		arch_pre=32
	elif [ "$architecture" = "~ARM~" ]
	then
		arch_pre=arm

	# Or use the local instance if nothing is specified.
	else
		arch_pre=none
	fi

	get_info_in_config () {
		echo "$(grep "^$1" "$script_dir/config" | cut --delimiter='=' --fields=2)"
	}

	# If an architecture is specified
	if [ "$arch_pre" != "none" ]
	then
		# Get the instance type for this architecture (SSH or LOCAL)
		instance=$(get_info_in_config "> $arch_pre.Instance=")
	fi

	# If a SSH instance type is asked
	if [ "$instance" = "SSH" ]
	then
		# List all instance in the config file by filtering "> x.arch.weight"
		list_instance=$(grep "^> .*$arch_pre.weight=" "$script_dir/config")

		local ssh=0
		while [ $ssh -eq 0 ]
		do
			CI_num=$(choose_a_instance "$list_instance")

			# Get all the informations for the connexion in the config file
			ssh_host=$(get_info_in_config "> $CI_num.$arch_pre.ssh_host=")
			ssh_user=$(get_info_in_config "> $CI_num.$arch_pre.ssh_user=")
			ssh_key=$(get_info_in_config "> $CI_num.$arch_pre.ssh_key=")
			pcheckci_path=$(get_info_in_config "> $CI_num.$arch_pre.pcheckci_path=")
			ssh_port=$(get_info_in_config "> $CI_num.$arch_pre.ssh_port=")

			# Try to connect first
			ssh $ssh_user@$ssh_host -p $ssh_port -i $ssh_key "exit"
			if [ "$?" -ne 0 ]; then
				echo "Failed to initiate an ssh connection on $ssh_host"
				list_instance="$(echo "$list_instance" | sed "/^> $CI_num./d")"
				if [ -z "$list_instance" ]; then
					echo "No ssh instances available..."
					break
				fi
			else
				echo "Connection to $ssh_host successful"
				ssh=1
			fi
		done

		# Start a test through SSH
		if [ $ssh -eq 1 ]; then
			PCHECK_SSH > "$cli_log" 2>&1
		fi

	# Or start a test on the local instance of Package check
	else

		PCHECK_LOCAL > "$cli_log" 2>&1
	fi
}

#=================================================
# Main test process
#=================================================

# The work list contains the next test to performed
work_list="$script_dir/work_list"

# If the list is not empty
if test -s "$work_list"
then

	#=================================================
	# Check the two lock files before continuing
	#=================================================

	lock_pcheckCI="$script_dir/CI.lock"
	lock_package_check="$script_dir/package_check/pcheck.lock"

	# If at least one lock file exist, cancel this execution
	if test -e "$lock_package_check" || test -e "$lock_pcheckCI"
	then

		# Simply print the date, for information
		date

		if test -e "$lock_package_check"; then
			echo "The file $(basename "$lock_package_check") exist. Package check is already used."
		fi

		if test -e "$lock_pcheckCI"; then
			echo "The file $(basename "$lock_pcheckCI") exist. Another test is already in progress."
		fi

		echo "Execution cancelled..."
		exit 0
	fi

	#=================================================
	# Create the file analyseCI_last_exec
	#=================================================

	analyseCI_indic="$script_dir/analyseCI_exec"
	if [ ! -e "$analyseCI_indic" ]
	then
		# Create the file for exec_indicator from analyseCI.sh
		touch "$analyseCI_indic"
		# And give enought right to allow analyseCI.sh to modify this file.
		chmod 666 "$analyseCI_indic"
	fi

	#=================================================
	# Parse the first line of work_list
	#=================================================

	# Read the first line of work_list
	repo=$(head --lines=1 "$work_list")
	# Get the id
	id=$(echo $repo | cut --delimiter=';' --fields=2)
	# Get the name of the test
	test_name=$(echo $repo | cut --delimiter=';' --fields=3)
	# Keep only the repositery
	repo=$(echo $repo | cut --delimiter=';' --fields=1)
	# Find the architecture name from the test name
	architecture="$(echo $(expr match "$test_name" '.*\((~.*~)\)') | cut --delimiter='(' --fields=2 | cut --delimiter=')' --fields=1)"

	#=================================================
	# Check the execution of analyseCI
	#=================================================

	check_analyseCI &

	#=================================================
	# Define the type of test
	#=================================================

	# Check if it's a test on testing
	if echo "$test_name" | grep --quiet "(testing)"
	then
		echo "Test on testing instance"
		# Add a subdir for the log file
		log_dir="logs_testing/"
		# Use a testing container
		"$script_dir/auto_build/switch_container.sh" testing

	# Or a test on unstable
	elif echo "$test_name" | grep --quiet "(unstable)"
	then
		echo "Test on unstable instance"
		# Add a subdir for the log file
		log_dir="logs_unstable/"
		# Use a unstable container
		"$script_dir/auto_build/switch_container.sh" unstable

	# Else, it's a test on stable
	else
		echo "Test on stable instance"
		# No subdir for the log file
		log_dir=""
		# Use a stable container
		"$script_dir/auto_build/switch_container.sh" stable
	fi

	#=================================================
	# Create the lock file
	#=================================================

	# Create the lock file, and fill it with id of the current test.
	echo "$id" > "$lock_pcheckCI"

	# And give enought right to allow analyseCI.sh to modify this file.
	chmod 666 "$lock_pcheckCI"

	#=================================================
	# Define the app log file
	#=================================================

	# From the repositery, remove http(s):// and replace all / by _ to build the log name
	app_log=${log_dir}$(echo "${repo#http*://}" | sed 's@/@_@g')$architecture.log
	# The complete log is the same of the previous log, with complete at the end.
	complete_app_log=${log_dir}$(basename --suffix=.log "$app_log")_complete.log



	#=================================================
	# Launch the test with Package check
	#=================================================

	# Simply print the date, for information
	date
	echo "A test with Package check will begin on $test_name (id: $id)"

	# Start the time counter
	set_timeout

	cli_log="$script_dir/package_check/Test_results_cli.log"

	# Exec package check according to the architecture
	EXEC_PCHECK




	#=================================================
	# Remove the first line of the work list
	#=================================================

	# After the test, it's removed from the work list
	grep --quiet "$id" "$work_list" & sed --in-place "/$id/d" "$work_list"

	#=================================================
	# Add in the cli log that the complete log was duplicated
	#=================================================

	echo -n "The complete log for this application was duplicated and is accessible at " >> "$cli_log"

	# If it's the official CI
	if test -e "$script_dir/auto_build/auto.conf"
	then
		domain=$(grep ^DOMAIN= "$script_dir/auto_build/auto.conf" | cut --delimiter='=' --fields=2)
		ci_path=$(grep ^CI_PATH= "$script_dir/auto_build/auto.conf" | cut --delimiter='=' --fields=2)
		# Print a url to access this log
		echo "https://$domain/$ci_path/logs/$complete_app_log" >> "$cli_log"

	# Else, it's simply a CI instance
	else
		# Print simply the path for this log
		echo "$script_dir/logs/$complete_app_log" >> "$cli_log"
	fi


	# Copy the cli log, next to the complete log
	cp "$cli_log" "$script_dir/logs/$app_log"


	# Add the name of the test at the beginning of the log
	sed --in-place "1i-> Test $test_name\n" "$script_dir/logs/$app_log"

	#=================================================
	# Finishing
	#=================================================

	date
	echo "Test finished on $test_name (id: $id)"

	# Inform analyseCI.sh that the test was finish
	echo Finish > "$lock_pcheckCI"

	# Start the time counter
	set_timeout
	# But shorten the time out
	timeout=120

	# Wait for the cleaning of the lock file. That means analyseCI.sh finished on its side.
	while test -s "$lock_pcheckCI"
	do
		# Check the timeout
		if ! timeout_expired
		then
			echo "analyseCI.sh was too long to liberate the lock file, break the lock file."
		fi
		sleep 5
	done

	# Inform check_analyseCI that the test is over
	echo Remove > "$lock_pcheckCI"

	#=================================================
	# Compare the level of this app
	#=================================================

	# Delay the process of comparaison of the level
	echo "\"$script_dir/auto_build/compare_level.sh\" \"$test_name\" \"$app_log\" >> \"$script_dir/auto_build/compare_level.log\" 2>&1" | at now + 5 min
fi
