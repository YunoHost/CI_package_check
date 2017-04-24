#!/bin/bash

#=================================================
# Grab the script directory
#=================================================

if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

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
CI_url=$(grep DOMAIN= "$script_dir/auto.conf" | cut --delimiter='=' --fields=2)/$(grep CI_PATH= "$script_dir/auto.conf" | cut --delimiter='=' --fields=2)

#=================================================
# Get the level from the log
#=================================================

# Find the line which contain the level
app_level="$(tac "$script_dir/../logs/$app_log" | grep "Level of this application: " --max-count=1)"
# And keep only the level
app_level="${app_level##*: }"

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
fi

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

	# Compare each app for this type with the level in stable
	# Read each app added in the list
	while read line
	do
		# Get the name of the test, from the list
		test_name=$(echo ${line%:*})
		# And remove the type, to keep only the name of the app
		test_name=$(echo ${test_name% \($type\)})
		# Get the level
		app_level=$(echo ${line##*:})

		# Get the level in the stable list
		stable_level=$(grep "^$test_name:" "$script_dir/list_level_stable" | cut --delimiter=: --fields=2)

		# Compare the levels
		if [ "$app_level" -ne "$stable_level" ]
		then
			# If the levels are different, add a line to the message to send
			echo "- Application $test_name change from $stable_level in stable to $app_level in $type. ($CI_url/logs/$app_log)" >> "$message_file"
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
		rm "$script_dir/list_level_$type"
		rm "$message_file"
	fi
fi

