#!/bin/bash

if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

if [ $# -ne 2 ]
then
    echo "This script need to take in argument the package which be tested and the name of the test."
    exit 1
fi

lock_CI="$script_dir/CI.lock"
lock_package_check="$script_dir/package_check/pcheck.lock"

CI_domain="$(grep DOMAIN= "$script_dir/auto_build/auto.conf" | cut --delimiter='=' --fields=2)"
CI_path="$(grep CI_PATH= "$script_dir/auto_build/auto.conf" | cut --delimiter='=' --fields=2)"
CI_url="https://$CI_domain/$CI_path"

timeout=$(grep "^timeout=" "$script_dir/config" | cut --delimiter="=" --fields=2)

#=================================================
# Delay the beginning of this script, to prevent concurrent executions
#=================================================

# Get 3 ramdom digit. To build a value between 001 and 999
milli_sleep=$(head --lines=20 /dev/urandom | tr --complement --delete '0-9' | head --bytes=3)
# And wait for this value in millisecond
sleep "0.$milli_sleep"

#============================
# Check / take the lock
#=============================

if [ -e $lock_CI ]
then
    lock_CI_PID="$(cat $lock_CI)"
    if [ -n "$lock_CI_PID" ]
    then
        if ps --pid $lock_CI_PID | grep --quiet $lock_CI_PID
        then
            echo -e "\e[91m\e[1m!!! Another analyseCI process is currently using the lock !!!\e[0m"
            exit 1
        else
            echo "Stale lock detected, removing it"
        fi
    fi
    rm -f $lock_CI
fi

echo "$$" > $lock_CI

#============================
# Test parameters
#=============================

# Repository
repo="$1"
# Test name
test_name="$2"
# Keep only the repositery
repo=$(echo $repo | cut --delimiter=';' --fields=1)
app="$(echo $test_name | awk '{print $1}')"

# Obviously that's too simple to have a unique nomenclature, so we have several of them
architecture="$(echo $(expr match "$test_name" '.*\((~.*~)\)') | cut --delimiter='(' --fields=2 | cut --delimiter=')' --fields=1)"
arch="amd64"
if [ "$architecture" = "~x86-32b~" ]
then
    arch="i386"
elif [ "$architecture" = "~ARM~" ]
then
    arch="armhf"
fi

ynh_branch="stable"
log_dir=""
if echo "$test_name" | grep --quiet "(testing)"
then
    local ynh_branch="testing"
    log_dir="logs_$ynh_branch/"
elif echo "$test_name" | grep --quiet "(unstable)"
then
    local ynh_branch="unstable"
    log_dir="logs_$ynh_branch/"
fi

# From the repositery, remove http(s):// and replace all / by _ to build the log name
log_name=${log_dir}$(echo "${repo#http*://}" | sed 's@[/ ]@_@g')$architecture
# The complete log is the same of the previous log, with complete at the end.
complete_app_log=${log_name}_complete.log
test_json_results=${log_name}_results.json

# Make sure /usr/local/bin is in the path, because that's where the lxc/lxd bin lives
export PATH=$PATH:/usr/local/bin

#=================================================
# Timeout handling utils
#=================================================

function watchdog() {
    local package_check_pid=$1
    # Start a loop while package check is working
    while ps --pid $package_check_pid | grep --quiet $package_check_pid
    do
        sleep 10

        if [ -e $lock_package_check ]
        then
            lock_timestamp="$(stat -c %Y $lock_package_check)"
            current_timestamp="$(date +%s)"
            if [[ "$(($current_timestamp > $lock_timestamp))" -lt "$timeout" ]]
            then
                pkill -9 $package_check_pid
                rm -f $lock_package_check
                exit_with_error "Package check aborted, timeout reached ($(( $timeout / 60 )) min)."
            fi
        fi
    done

    [ -e "$script_dir/package_check/results.json" ] \
    || exit_with_error "It looks like package_check did not finish properly ..."
}

function exit_with_error() {
    local message="$1"

    echo -e "\e[91m\e[1m!!! $message !!!\e[0m"
    ARCH="$arch" YNH_BRANCH="$ynh_branch" "$script_dir/package_check/package_check.sh" --force-stop
    exit 1
}

#=================================================
# The actual testing ...
#=================================================

# Exec package check according to the architecture
echo "$(date) - Starting a test for $app on architecture $arch with yunohost $ynh_branch"

rm -f "$script_dir/package_check/Complete.log"
rm -f "$script_dir/package_check/results.json"

ARCH="$arch" YNH_BRANCH="$ynh_branch" nice --adjustment=10 "$script_dir/package_check/package_check.sh" "$repo" 2>&1 &

watchdog $!

# Copy the complete log
cp "$script_dir/package_check/Complete.log" "$script_dir/logs/$complete_app_log"
cp "$script_dir/package_check/results.json" "$script_dir/logs/$test_json_results"

if [ -n "$CI_url" ]
then
    full_log_path="https://$CI_url/logs/$complete_app_log"
else
    full_log_path="$script_dir/logs/$complete_app_log"
fi

echo "$(date) - Test completed"
echo "The complete log for this application was duplicated and is accessible at $full_log_path"

#=================================================
# Check / update level of the app
#=================================================

public_result_list="$script_dir/logs/list_level_${ynh_branch}_$arch.json"
[ -e "$public_result_list" ] || echo "{}" > "$public_result_list"

# Get new level and previous level
app_level=""
previous_level="$(jq -r ".$app" "$public_result_list")"

if [ -e "$script_dir/logs/$test_json_results" ]
then
    app_level="$(jq -r ".level" "$script_dir/logs/$test_json_results")"
    cp "$script_dir/auto_build/badges/level${app_level}.svg" "$script_dir/logs/$app.svg"
    # Update/add the results from package_check in the public result list
    jq --slurpfile results "$script_dir/logs/$test_json_results" ".\"$app\"=\$results" > $public_result_list.new
    mv $public_result_list.new $public_result_list
fi

#=================================================
# Send update on XMPP
#=================================================

# We post message on XMPP if we're running for tests on stable/amd64
xmpppost="$script_dir/auto_build/xmpp_bot/xmpp_post.sh"
if [[ -e "$xmpppost" ]] && [[ "$ynh_branch" == "stable" ]] && [[ "$arch" == "amd64" ]]
then
    message="Application $app_name "

    if [ -z "$app_level" ]; then
        message="Failed to test $app_name"
    elif [ "$app_level" -eq 0 ]; then
        message+="completely failed the continuous integration tests"
    elif [ -z "$previous_level" ]; then
        message+="just reached the level $app_level"
    elif [ $app_level -gt $previous_level ]; then
        message+="rises from level $previous_level to level $app_level"
    elif [ $app_level -lt $previous_level ]; then
        message+="goes down from level $previous_level to level $app_level"
    else
        message+="stays at level $app_level"
    fi

    message+=" on $CI_url/job/$id"

    "$xmpppost" "$message"
fi

#==================
# Free the lock
#==================

rm -f $lock_CI
