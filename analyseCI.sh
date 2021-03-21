#!/bin/bash

if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

cd $script_dir

if [ $# -ne 3 ]
then
    echo "This script need to take in argument the package which be tested and the name of the test."
    exit 1
fi

lock_CI="./CI.lock"
lock_package_check="./package_check/pcheck.lock"

TIMEOUT="$(grep "^TIMEOUT=" "./config" | cut --delimiter="=" --fields=2)"
CI_URL="https://$(grep "^CI_URL=" "./config" | cut --delimiter='=' --fields=2)"
ynh_branch="$(grep "^YNH_BRANCH=" "./config" | cut --delimiter="=" --fields=2)"
arch="$(grep "^ARCH=" "./config" | cut --delimiter="=" --fields=2)"

#=================================================
# Delay the beginning of this script, to prevent concurrent executions
#=================================================

# Get 3 ramdom digit. To build a value between 001 and 999
milli_sleep=$(head --lines=20 /dev/urandom | tr --complement --delete '0-9' | head --bytes=3)
# And wait for this value in millisecond
sleep "10.$milli_sleep"

#============================
# Check / take the lock
#=============================

if [ -e $lock_CI ]
then
    lock_CI_PID="$(cat $lock_CI)"
    if [ -n "$lock_CI_PID" ]
    then
	# We check that the corresponding PID is still running AND that the PPid is not 1 ..
	# If the PPid is 1, it tends to indicate that a previous analyseCI is still running and was not killed, and therefore got adopted by init.
	# This typically happens when the job is cancelled / restarted .. though we should have a better way of handling cancellation from yunorunner directly :/
        if ps --pid $lock_CI_PID | grep --quiet $lock_CI_PID && [[ $(grep PPid /proc/${lock_CI_PID}/status | awk '{print $2}') != "1" ]]
        then
            echo -e "\e[91m\e[1m!!! Another analyseCI process is currently using the lock !!!\e[0m"
            exit 1
        fi
    fi
    [[ $(grep PPid /proc/$(lock_CI_PID)/status | awk '{print $2}') != "1" ]] && { echo "Killing stale analyseCI process ..."; kill -s SIGTERM $lock_CI_PID; sleep 30; }
    echo "Removing stale lock"
    rm -f $lock_CI
fi

echo "$$" > $lock_CI

#============================
# Cleanup after exit/kill
#=============================

function cleanup()
{
    rm $lock_CI

    if [ -n "$package_check_pid" ]
    then
        kill -s SIGTERM $package_check_pid
        ARCH="$arch" YNH_BRANCH="$ynh_branch" "./package_check/package_check.sh" --force-stop
    fi
}

trap cleanup EXIT
trap 'exit 2' TERM KILL

#============================
# Test parameters
#=============================

repo="$1"
test_name="$2"
job_id="$3"

# Keep only the repositery
repo=$(echo $repo | cut --delimiter=';' --fields=1)
app="$(echo $test_name | awk '{print $1}')"

test_full_log=${app}_${arch}_${ynh_branch}_complete.log
test_json_results=${app}_${arch}_${ynh_branch}_results.json
test_url="$CI_URL/job/$job_id"

xmpp_notify="./lib/xmpp_notify.py"
is_main_ci="false"
if [[ "$ynh_branch" == "stable" ]] && [[ "$arch" == "amd64" ]]
then
    is_main_ci="true"
fi

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
            if [[ "$(($current_timestamp - $lock_timestamp))" -gt "$TIMEOUT" ]]
            then
                kill -s SIGTERM $package_check_pid
                rm -f $lock_package_check
                force_stop "Package check aborted, timeout reached ($(( $TIMEOUT / 60 )) min)."
                return 1
            fi
        fi
    done

    if [ ! -e "./package_check/results.json" ]
    then
        force_stop "It looks like package_check did not finish properly ... on $test_url"
        return 1
    fi
}

function force_stop() {
    local message="$1"

    echo -e "\e[91m\e[1m!!! $message !!!\e[0m"
    if [[ $is_main_ci == "true" ]]
    then
        "$xmpp_notify" "While testing $app: $message"
    fi

    ARCH="$arch" YNH_BRANCH="$ynh_branch" "./package_check/package_check.sh" --force-stop
}

#=================================================
# The actual testing ...
#=================================================

# Exec package check according to the architecture
echo "$(date) - Starting a test for $app on architecture $arch with yunohost $ynh_branch"

rm -f "./package_check/Complete.log"
rm -f "./package_check/results.json"

# Here we use a weird trick with 'script -qefc'
# The reason is that :
# if running the command in background (with &) the corresponding command *won't be in a tty* (not sure exactly)
# therefore later, the command lxc exec -t *won't be in a tty* (despite the -t) and command outputs will appear empty...
# Instead, with the magic of script -qefc we can pretend to be in a tty somehow...
# Adapted from https://stackoverflow.com/questions/32910661/pretend-to-be-a-tty-in-bash-for-any-command
cmd="ARCH=$arch YNH_BRANCH=$ynh_branch nice --adjustment=10 './package_check/package_check.sh' '$repo' 2>&1"
script -qefc "$cmd" &

watchdog $! || exit 1

# Copy the complete log
cp "./package_check/Complete.log" "./logs/$test_full_log"
cp "./package_check/results.json" "./logs/$test_json_results"

if [ -n "$CI_URL" ]
then
    full_log_path="$CI_URL/logs/$test_full_log"
else
    full_log_path="$(pwd)/logs/$test_full_log"
fi

echo "The complete log for this application was duplicated and is accessible at $full_log_path"

echo ""
echo "-------------------------------------------"
echo ""

#=================================================
# Check / update level of the app
#=================================================

public_result_list="./logs/list_level_${ynh_branch}_$arch.json"
[ -s "$public_result_list" ] || echo "{}" > "$public_result_list"

# Check that we have a valid json...
jq -e '' "./logs/$test_json_results" >/dev/null 2>/dev/null && bad_json="false" || bad_json="true"

# Get new level and previous level
app_level="$(jq -r ".level" "./logs/$test_json_results")"
previous_level="$(jq -r ".$app" "$public_result_list")"

# We post message on XMPP if we're running for tests on stable/amd64
message="Application $app "

if [ "$bad_json" == "true" ] || [ "$app_level" -eq 0 ]; then
    message+="completely failed the continuous integration tests"
elif [ -z "$previous_level" ]; then
    message+="just reached level $app_level !"
elif [ $app_level -gt $previous_level ]; then
    message+="rises from level $previous_level to level $app_level"
elif [ $app_level -lt $previous_level ]; then
    message+="goes down from level $previous_level to level $app_level"
else
    message+="stays at level $app_level"
fi

message+=" on $test_url"

echo $message

# Send XMPP notification
if [[ "$is_main_ci" == "true" ]]
then
    [ -e "$xmpp_notify" ] && "$xmpp_notify" "$message"
    cp "./badges/level${app_level}.svg" "./logs/$app.svg"
fi

# Update/add the results from package_check in the public result list
if [ "$bad_json" == "false" ]
then
    jq --argfile results "./logs/$test_json_results" ".\"$app\"=\$results" $public_result_list > $public_result_list.new
    mv $public_result_list.new $public_result_list
fi

# Annnd we're done !
echo "$(date) - Test completed"

[ "$app_level" -gt 5 ] && exit 0 || exit 1
