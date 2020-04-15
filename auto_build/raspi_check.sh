#!/bin/bash

#=================================================
# Grab the script directory
#=================================================

script_dir="$(dirname $(realpath $0))"

#=================================================
# Fucntion to read the config file
#=================================================

get_info_in_config () {
    echo "$(grep --max-count=1 "^$1" "$script_dir/../config" | cut --delimiter='=' --fields=2)"
}

#=================================================
# Check each raspi in the list
#=================================================

mail="mail"
echo "News about RaspberryPi fleet for ci-apps-arm" > "$mail"
report=0

# Loop 1: Check non commented raspi
# Loop 2: Check previously commented raspi
for loop in `seq 1 2`
do
    echo "Loop=$loop"
    while read CI_num <&3
    do
        # In loop 1, ignore commented instances
        if [ "${CI_num:0:1}" == "#" ] && [ $loop -eq 1 ]; then
            continue

        # In loop 2, ignore non-commented instances
        elif [ "${CI_num:0:1}" != "#" ] && [ $loop -eq 2 ]; then
            continue
        fi

        # Keep only the number of the instance
        CI_num="$(echo "$CI_num" | sed 's/.*\([[:digit:]]\)\.arm.*/\1/g')"

        # Get all the informations for the connexion in the config file
        if [ $loop -eq 1 ]; then
            starter="[ ]*"
        else
            starter="[# ]*"
        fi
        ssh_host=$(get_info_in_config "$starter> $CI_num.arm.ssh_host=")
        ssh_user=$(get_info_in_config "$starter> $CI_num.arm.ssh_user=")
        ssh_key=$(get_info_in_config "$starter> $CI_num.arm.ssh_key=")
        ssh_port=$(get_info_in_config "$starter> $CI_num.arm.ssh_port=")

        # Try to connect first, and get the load average for this instance
        echo "Check the connection to $ssh_host"
        result="$(ssh $ssh_user@$ssh_host -p $ssh_port -i $ssh_key "uptime" 2>&1)"
        exit_code=$?
        # In loop 1, report not working instances
        if [ "$exit_code" -ne 0 ] && [ $loop -eq 1 ]
        then
            echo -e "\nFailed to initiate a ssh connection on $ssh_host" >> "$mail"
            echo -e "With the error:\n$result" >> "$mail"
            report=1

        # In loop 2, report instances working again
        elif [ "$exit_code" -eq 0 ] && [ $loop -eq 2 ]
        then
            echo -e "\nDeactivated instance $ssh_host seems to work again" >> "$mail"
            report=1
        fi
    done 3<<< "$(grep "> .*arm.ssh_host=" "$script_dir/../config")"
done

#=================================================
# Send the report by email
#=================================================

if [ $report -ne 0 ]
then
    # Get the mail the config file
    recipient=$(cat "$script_dir/auto.conf" | grep MAIL_DEST= | cut -d '=' -f2)
    # Send an alert by email
    mail -s "[YunoHost] Rpi status report for CI-apps-arm" "$recipient" <<< "$(cat "$mail")"
fi
