#!/bin/bash

# Récupère le dossier du script
script_dir="$(dirname $(realpath $0))"

# Default user directory
user_dir="/home/yunohost.app/ssh_chroot_directories"

# Default quota
size=1G

read -p "Give the name for this new user: " ssh_user
ssh_user=${ssh_user//[^[:alnum:].\-_]/_}
read -p "And its public ssh key: " pub_key

user_dir="$user_dir/$ssh_user"

/opt/yunohost/ssh_chroot_dir/chroot_manager.sh adduser --name $ssh_user --sshkey "$pub_key" --directory "$user_dir" --quota $size
