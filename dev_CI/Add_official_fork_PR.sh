#!/bin/bash

official_fork_path=/home/yunohost.app/ssh_chroot_directories/Official_fork/data/

read -p "Forked repository: " repo
read -p "Branch: " branch
read -p "PR number: " PR_number

clone_directory="$official_fork_path/$(basename $repo) PR$PR_number"

git clone $repo "$clone_directory"
(cd "$clone_directory"; git checkout $branch)
