#!/bin/bash

#=================================================
# Grab the script directory
#=================================================

if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

#=================================================
# Get variables
#=================================================

# The first argument is the type of log to compare with stable. It can be unstable or testing
type=$1

if [ "$type" != "testing" ] || [ "$type" != "unstable" ]
then
	echo "This script need as argument either \'testing\' or \'unstable\'"
	exit 1
fi

#=================================================
# List all log for this type
#=================================================

while read app_log
do
	if ! grep -q "_complete.log$" <<< "$app_log"	# Ignore les logs "complete", ne traite que les autres fichiers.
	then
		test_name=$(grep "^-> Test " < "$script_dir/../logs/logs_$type/$app_log")	# Récupère le nom du test, ajouté au début du log
		test_name=${app#-> Test }	# Supprime "-> Test " pour garder uniquement le nom du test
	fi
done <<< "$(ls -1 "$script_dir/../logs/logs_$type")"

#=================================================
# Call compare_level.sh for each app
#=================================================

"$script_dir/compare_level.sh" "$test_name" "$app_log"
