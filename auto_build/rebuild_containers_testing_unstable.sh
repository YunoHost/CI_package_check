#!/bin/bash

# Build a CI with YunoHost, Jenkins and CI_package_check
# Then add a build for each app.

# Get the path of this script
script_dir="$(dirname $(realpath $0))"

echo_bold () {
	echo -e "\e[1m$1\e[0m"
}

# Put lock files to prevent any usage of package check during the installation.
touch "$script_dir/../CI.lock"
touch "$script_dir/../package_check/pcheck.lock"

echo_bold "Remove snapshots"
sudo rm -rf /var/lib/lxcsnaps/pcheck_stable
sudo rm -rf /var/lib/lxcsnaps/pcheck_testing
sudo rm -rf /var/lib/lxcsnaps/pcheck_unstable
sudo rm -rf /var/lib/lxcsnaps/$lxc_name

# Installation of Package_check
echo_bold "Installation of Package check with its CI script"
"$script_dir/../package_check/sub_scripts/lxc_build.sh"

# Move the snapshot and replace it by a symbolic link
# The symbolic link will allow to switch between Stable, Testing and Unstable container.
# We need it even for Stable only, because the CI script works with the symbolic link.

echo_bold "Replace the snapshot by a symbolic link"
lxc_name=$(grep LXC_NAME= "$script_dir/../package_check/config" | cut -d '=' -f2)
sudo mv /var/lib/lxcsnaps/$lxc_name /var/lib/lxcsnaps/pcheck_stable
sudo ln -s /var/lib/lxcsnaps/pcheck_stable /var/lib/lxcsnaps/$lxc_name

# Create testing and unstable containers
# We will not create any new containers, but only duplicate the main snapshot, then modify it to create a testing and a unstable snapshot.
# Then, to work, the CI will only change the snapshot pointed by the symbolic link.

for change_version in testing unstable
do
	# Add a new directory for the snapshot
	sudo mkdir -p /var/lib/lxcsnaps/pcheck_$change_version

	echo_bold "> Copy the stable snapshot to create a snapshot for $change_version"
	sudo cp -a /var/lib/lxcsnaps/pcheck_stable/snap0 /var/lib/lxcsnaps/pcheck_$change_version/snap0

	echo_bold "> Configure repositories for $change_version"
	if [ $change_version == testing ]; then
		source="testing"
	else
		source="testing unstable"
	fi
	sudo echo "deb http://repo.yunohost.org/debian/ jessie stable $source" | sudo tee /var/lib/lxcsnaps/pcheck_$change_version/snap0/rootfs/etc/apt/sources.list.d/yunohost.list

	# Remove lock files to allow upgrade
	sudo rm -f "$script_dir/../package_check/pcheck.lock" "$script_dir/../CI.lock"

	echo_bold "> Upgrade the container $change_version"
	sudo "$script_dir/auto_upgrade_container.sh" $change_version

	# Put back the lock files
	touch "$script_dir/../CI.lock" "$script_dir/../package_check/pcheck.lock"
done

# Remove the stable container for a Testing_Unstable CI.
if [ "$ci_type" = "Testing_Unstable" ]
then
	sudo rm -r /var/lib/lxcsnaps/pcheck_stable
fi

# Remove lock files
sudo rm -f "$script_dir/../package_check/pcheck.lock"
sudo rm -f "$script_dir/../CI.lock"

echo_bold "Check containers"
sudo "$script_dir/switch_container.sh" testing
sudo "$script_dir/../package_check/sub_scripts/lxc_check.sh"
sudo "$script_dir/switch_container.sh" unstable
sudo "$script_dir/../package_check/sub_scripts/lxc_check.sh"
