#!/bin/bash

#=================================================
# Grab the script directory
#=================================================

if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

#=================================================
# Get the list and check for any modifications
#=================================================

# Get the apps list from app.yunohost.org
wget -nv https://app.yunohost.org/default/v2/apps.json -O "$script_dir/apps.json"

do_update=1
if [ -e "$script_dir/apps.json.md5" ]
then
    if md5sum --check --status "$script_dir/apps.json.md5"
    then
        echo "No changes into the app list since the last execution."
        do_update=0
    fi
fi

if [ $do_update -eq 1 ]
then
    md5sum "$script_dir/apps.json" > "$script_dir/apps.json.md5"

    #=================================================
    # Update badges for all apps
    #=================================================

    # Parse each app into the list
    while read app
    do
        # Get the high_quality tag for this app
        high_quality=$(jq --raw-output ".apps[\"$app\"] | .high_quality" "$script_dir/apps.json")

        # Get the status for this app
        state=$(jq --raw-output ".apps[\"$app\"] | .state" "$script_dir/apps.json")
        # Get the maintained status for this app
        maintained=$(jq --raw-output ".apps[\"$app\"] | .maintained" "$script_dir/apps.json")

        # Update the tag for the status
        if [ "$high_quality" == "true" ] && [ "$state" == "working" ] && [ "$maintained" == "true" ]
        then
            # If the app has the high_quality tag, is working and is maintained.
            # Then, the app si a high quality one and earn its tag
            state_badge=high_quality
        else
            state_badge=$state
        fi

        # Update the tag for the maintain status
        if [ "$maintained" == "true" ]
        then
            maintain_badge=maintained
        elif [ "$maintained" == "false" ]
        then
            maintain_badge=orphaned
        else
            maintain_badge=$maintained
        fi

        cp "$script_dir/badges/$state_badge.svg" "$script_dir/badges/${app}.status.svg"
        cp "$script_dir/badges/$maintain_badge.svg" "$script_dir/badges/${app}.maintain.svg"

    # List all apps from the list, by getting manifest ID.
    done <<< "$(jq --raw-output ".apps[] | .manifest.id" "$script_dir/apps.json")"
fi
