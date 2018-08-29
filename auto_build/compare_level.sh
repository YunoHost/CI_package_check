#!/bin/bash

#=================================================
# Grab the script directory
#=================================================

script_dir="$(dirname $(realpath $0))"

#=================================================
# Get variables
#=================================================

# The first argument is the name of the test. The third field of work_list
test_name=$1
# The second argument is the relative path of the log for this app
app_log=$2

# Identify the type of test
if echo "$test_name" | grep --quiet "(testing)"; then
	type=testing
elif echo "$test_name" | grep --quiet "(unstable)"; then
	type=unstable
else
	type=stable
fi

# Get the url of the CI from the config file
CI_url="https://$(grep DOMAIN= "$script_dir/auto.conf" | cut --delimiter='=' --fields=2)/$(grep CI_PATH= "$script_dir/auto.conf" | cut --delimiter='=' --fields=2)"

#=================================================
# Get the level from the log
#=================================================

# Find the line which contain the level
app_level="$(tac "$script_dir/../logs/$app_log" | grep "Level of this application: " --max-count=1)"
# And keep only the level
app_level="${app_level##*: }"
app_level=$(echo "$app_level" | cut -d' ' -f1)

#=================================================
# Store the level in a list
#=================================================

# Each type have its own list
list_file="$script_dir/list_level_$type"

# If a level has been found
if [ -n "$app_level" ]
then

	# Create the list if it doesn't exist
	if [ ! -e "$list_file" ]; then
		touch "$list_file"
	fi

	# Try to find this app in the list
	if grep --quiet "^$test_name:" "$list_file"
	then

		# If the app has been found, replace the level
		sed --in-place "s/^$test_name:.*/$test_name:$app_level/" "$list_file"

	# Else, add this app to the list
	else
		echo "$test_name:$app_level" >> "$list_file"
	fi

	# Copy the list stable to the public directory 'logs'
	if [ "$type" = "stable" ]
	then
		cp "$list_file" "$script_dir/../logs/list_level_stable_raw"
	fi
fi

#=================================================
# Store the level and other infos in a public list
#=================================================

# Check the global result of the test
# Success by default
success=1
# Search for some FAIL in the final results
# But, ignore the line of package linter.
if grep "FAIL$" "$script_dir/../logs/$app_log" | grep --invert-match "Package linter" | grep --quiet "FAIL$"
then
	# If a fail was find, the test failed.
	success=0
# Search also for a "PCHECK_AVORTED". That means the script pcheckCI was aborted by a timeout.
elif grep "PCHECK_AVORTED" "$script_dir/../logs/$app_log"
then
	success=0
# And, finally, check if at least one test was a success.
elif ! grep "SUCCESS$" "$script_dir/../logs/$app_log" | grep --invert-match "Package linter" | grep --quiet "SUCCESS$"
then
	success=0
fi

# Declare an array of 16 cells, for the result of each tests
tests_results=(? ? ? ? ? ? ? ? ? ? ? ? ? ? ? ?)

# If no level found
if [ -z "$app_level" ]; then
	app_level="?"
else
	# Find the detailled results of this test
	while read detailled_level
	do
		# Remove the 4 first characters, which are only a color indication
		detailled_level="${detailled_level:4}"
		case "${detailled_level%%:*}" in
			"age linter" ) index=0 ;;
			"Installation" ) index=1 ;;
			"Deleting" ) index=2 ;;
			"Installation in a sub path" ) index=3 ;;
			"Deleting from a sub path" ) index=4 ;;
			"Installation on the root" ) index=5 ;;
			"Deleting from root" ) index=6 ;;
			"Upgrade" ) index=7 ;;
			"Installation in private mode" ) index=8 ;;
			"Installation in public mode" ) index=9 ;;
			"Multi-instance installations" ) index=10 ;;
			"Malformed path" ) index=11 ;;
			"Port already used" ) index=12 ;;
			"Backup" ) index=13 ;;
			"Restore" ) index=14 ;;
			"Change URL" ) index=15 ;;
			*) index=-1 ;;
		esac

		if [ $index -ge 0 ]
		then
			if echo "$detailled_level" | grep --quiet "SUCCESS"; then
				# Can be a success only if there no failure on this test before.
				if [ "${tests_results[$index]}" != "0" ]; then
					tests_results[$index]=1
				fi
			elif echo "$detailled_level" | grep --quiet "FAIL"; then
				tests_results[$index]=0
			else
				if [ "${tests_results[$index]}" == "?" ]; then
					# Result unknow if there no success or fail before.
					tests_results[$index]="-"
				fi
			fi
		fi
	done <<< "$(tac "$script_dir/../logs/$app_log" | grep "Level of this application: " --after-context=20)"
fi

# Each type have its own list
public_list_file="$script_dir/../logs/list_level_$type"

# Remove the previous entry for this app
sed --in-place "/^$test_name;/d" "$public_list_file"
sed --in-place "/\"$test_name\":/d" "$public_list_file.json"

# Then add this app to the list
echo "$test_name;level=$app_level;success=$success;detailled_success=${tests_results[@]};date=$(date) ($(date +%s))" >> "$public_list_file"

# Rebuild the array for the (fucking ?) json format
for i in ${tests_results[*]}
do
	tests_results_json="$tests_results_json \"$i\","
done
# Remove the last comma
tests_results_json=${tests_results_json%,}
echo "{ \"$test_name\": { \"level\": $app_level, \"success\": $success, \"detailled_success\": [$tests_results_json ], \"date\": \"$(date)\", \"timestamp\": $(date +%s) } }" >> "$public_list_file.json"

#=================================================
# For testing and unstable, compare with stable
#=================================================

message_file="$script_dir/diff_level_send"

if [ "$type" = "testing" ] || [ "$type" = "unstable" ]
then

	# Check if another test on the same container is waiting in the work_list
	if grep --quiet "($type)" "$script_dir/../work_list"
	then
		# Finish the script, the next execution will continue.
		exit 0
	fi

	# If it isn't a Mixed_content CI (stable, testing and unstable on the same server)
	if [ "$(grep CI_TYPE "$script_dir/auto_build/auto.conf" | cut -d '=' -f2)" != "Mixed_content" ]
	then
		# Get the list stable from the official CI
		wget https://ci-apps.yunohost.org/ci/logs/list_level_stable_raw --output-document=$script_dir/list_level_stable
	fi

	# Compare each app for this type with the level in stable
	# Read each app added in the list
	while read line
	do
		# Get the name of the test, from the list
		test_name=$(echo ${line%:*})
		# And remove the type, to keep only the name of the app
		stable_test_name=$(echo ${test_name% \($type\)})
		# Get the level
		app_level=$(echo ${line##*:})

		# Get the level in the stable list
		stable_level=$(grep "^$stable_test_name:" "$script_dir/list_level_stable" | cut --delimiter=: --fields=2)

		# Compare the levels
		if [ "$app_level" -ne "$stable_level" ]
		then
			# If the levels are different, add a line to the message to send
			echo "- Application $stable_test_name change from $stable_level in stable to $app_level in $type. ($CI_url/$test_name)" >> "$message_file"
		fi
	done < "$list_file"

	# Remove the list after the comparaison
	rm "$list_file"
fi

#=================================================
# Notify on xmpp apps room
#=================================================

# If the message file is not empty
if [ -s "$message_file" ]
then

	# If the message has more than one line, store it into a pastebin
	if [ $(wc --lines "$message_file" | cut --delimiter=' ' --fields=1) -gt 1 ]
	then
		# Store the message into a pastebin
		paste=$(cat "$message_file" | yunopaste)
		# And send only its adress
		echo "Level difference between stable and $type: $paste" > "$message_file"
	fi

	xmpppost="$script_dir/xmpp_bot/xmpp_post.sh"
	# Send via xmpp only if the script was find
	if [ -e "$xmpppost" ]
	then
		"$xmpppost" "$(cat "$message_file")"

		# Remove the list of levels and the message file
		rm "$message_file"
	fi
fi

