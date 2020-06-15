#!/usr/bin/env bash

# Usage:
# send_to_dev_ci.sh
#    Use without arguments, the script will use the static list at the end of script
#
# send_to_dev_ci.sh my_app my_other_app "the directory/which/contains/my_third_app"
#    Use with arguments, each argument will be considered as an app to send to the CI.

# Get the path of this script
script_dir="$(dirname "$(realpath "$0")")"

# Get potential arguments and store them into an array
if [ $# -ge 1 ]; then
    folders_to_send=("$@")
else
    folders_to_send=(
        "$script_dir/APP1"
        "$script_dir/APP2"
        "$script_dir/APP3"
    )
fi

ssh_user=USERNAME
ssh_host=ci-apps-dev.yunohost.org
ssh_port=22
ssh_key=~/.ssh/USER_SSH_KEY
distant_dir=/data
SSHSOCKET=~/.ssh/ssh-socket-%r-%h-%p

SEND_TO_CI () {
    # Dirs specified as local[:distant]
    # distant = basename(local) if not specified

    IFS=':' read -ra dirs <<< "${1}"

    # Rsync needs trailing slash
    source_dir="$(realpath "${dirs[0]}")"
    [[ "${source_dir}" != */ ]] && source_dir="${source_dir}/"

    target_dir="${dirs[1]}"
    : "${target_dir:="$(basename "${source_dir}")"}"

    echo "============================"
    echo ">>> Sending $source_dir to $target_dir"
    rsync -avzhuE -c --progress --delete --exclude=".git" "${source_dir}" -e "ssh -i $ssh_key -p $ssh_port -o ControlPath=$SSHSOCKET"  $ssh_user@$ssh_host:"$distant_dir/$target_dir"
    echo "============="
    echo "Build should show up here once it starts:"
    echo "https://$ssh_host/jenkins/job/${target_dir}%20(${ssh_user})/lastBuild/console"
}

echo "Opening connection"
if ! ssh $ssh_user@$ssh_host -p $ssh_port -i $ssh_key -f -M -N -o ControlPath=$SSHSOCKET; then
    # If the user wait too long, the connection will fail.
    # Same player try again
    ssh $ssh_user@$ssh_host -p $ssh_port -i $ssh_key -f -M -N -o ControlPath=$SSHSOCKET
fi

# Read each arguments separately
for folder in "${folders_to_send[@]}"; do
    SEND_TO_CI "$folder"
done

echo "Closing connection"
ssh $ssh_user@$ssh_host -p $ssh_port -i $ssh_key -S $SSHSOCKET -O exit
