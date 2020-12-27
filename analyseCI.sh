#!/bin/bash

if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

cd $script_dir

if [ $# -ne 2 ]
then
    echo "This script need to take in argument the package which be tested and the name of the test."
    exit 1
fi

lock_CI="./CI.lock"
lock_package_check="./package_check/pcheck.lock"

CI_domain="$(grep DOMAIN= "./config" | cut --delimiter='=' --fields=2)"
CI_path="$(grep CI_PATH= "./config" | cut --delimiter='=' --fields=2)"
TIMEOUT="$(grep "^TIMEOUT=" "./config" | cut --delimiter="=" --fields=2)"

CI_url="https://$CI_domain/$CI_path"

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
# Cleanup after exit/kill
#=============================

function cleanup()
{
    rm $lock_CI
}

trap cleanup EXIT
trap 'exit 2' TERM KILL

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

xmpppost="./xmpp_bot/xmpp_post.sh"
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
        force_stop "It looks like package_check did not finish properly ..."
        return 1
    fi
}

function force_stop() {
    local message="$1"

    echo -e "\e[91m\e[1m!!! $message !!!\e[0m"
    if [[ $is_main_ci == "true" ]]
    then
        "$xmpppost" "While testing $app: $message"
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
cp "./package_check/Complete.log" "./logs/$complete_app_log"
cp "./package_check/results.json" "./logs/$test_json_results"

if [ -n "$CI_url" ]
then
    full_log_path="$CI_url/logs/$complete_app_log"
else
    full_log_path="$(pwd)/logs/$complete_app_log"
fi

echo "The complete log for this application was duplicated and is accessible at $full_log_path"

echo ""
echo "-------------------------------------------"
echo ""

#=================================================
# Check / update level of the app
#=================================================

public_result_list="./logs/list_level_${ynh_branch}_$arch.json"
[ -e "$public_result_list" ] || echo "{}" > "$public_result_list"

# Get new level and previous level
app_level="$(jq -r ".level" "./logs/$test_json_results")"
previous_level="$(jq -r ".$app" "$public_result_list")"

# We post message on XMPP if we're running for tests on stable/amd64
message="Application $app "

if [ "$app_level" -eq 0 ]; then
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

# FIXME : how to get the $id from yunorunner...
message+=" on $CI_url/job/$id"

echo $message

# Send XMPP notification
if [[ "$is_main_ci" == "true" ]]
then
    [ -e "$xmpppost" ] && "$xmpppost" "$message"
    cp "./badges/level${app_level}.svg" "./logs/$app.svg"
fi

# Update/add the results from package_check in the public result list
jq --slurpfile results "./logs/$test_json_results" ".\"$app\"=\$results" $public_result_list > $public_result_list.new
mv $public_result_list.new $public_result_list

# Annnd we're done !
echo "$(date) - Test completed"
