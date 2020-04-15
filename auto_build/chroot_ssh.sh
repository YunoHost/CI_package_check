#!/bin/bash

# Ce script permet de mettre en place un CI_package_check dans un dossier dédié à un user dont l'accès SSH est chrooté à ce dossier.
# Cela permet de mettre en place des instances CI_package_check secondaires pour le CI officiel sans pour autant donner un accès complet à la machine.

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

user_ssh=pcheck
chroot_dir=/home/$user_ssh

# Remove the chroot
if [ $# -gt 0 ]
then
	if [ "$1" == "--remove" ]
	then
		echo -e "\e[1m> Supprime le chroot pour l'utilisateur $user_ssh.\e[0m"

		echo -e "\e[1m> Supprime CI_package_check.\e[0m"
		sudo "$chroot_dir/CI_package_check/remove_CI.sh"

		echo -e "\e[1m> Supprime l'utilisateur $user_ssh.\e[0m"
		sudo userdel --remove $user_ssh
		sudo groupdel $user_ssh

		echo -e "\e[1m> Supprime le chroot dans la config ssh.\e[0m"
		sudo sed -i "/.*# $user_ssh CI/d" /etc/ssh/sshd_config

		echo -e "\e[1m> Démonte les interfaces loadavg et uptime de proc.\e[0m"
		sudo umount --force $chroot_dir/proc/loadavg
		sudo umount --force $chroot_dir/proc/uptime

		echo -e "\e[1m> Supprime le dossier de $user_ssh.\e[0m"
		if [ -n "$user_ssh" ]
		then
			sudo rm -r /home/$user_ssh
		fi

		echo -e "\e[1m> Nettoye le fstab.\e[0m"
		# Supprime le commentaire en tête
		sudo sed -i '/#CI# /d' /etc/fstab
		# Puis les 2 lignes de mount. les / sont remplacés par \/ pour rentrer dans le sed
		sudo sed -i "/${chroot_dir//\//\\\/}\/proc/d" /etc/fstab

		exit 0
	fi
fi

echo -e "\e[1m> Vérifie que le chroot n'existe pas déjà.\e[0m"
if [ -e "$chroot_dir" ]
then
	echo -e "\e[1m> Un dossier de chroot existe déjà.\e[0m"
	echo -e "\e[1m> Il va être supprimé préalablement.\e[0m"
	# Backup the config file, to avoid to destroy it.
	sudo mv "$chroot_dir/CI_package_check/package_check/config" "$script_dir/config.backup"
	"$script_dir/chroot_ssh.sh" --remove
fi


echo -e "\e[1m> Installe mlocate.\e[0m"
sudo apt-get update
sudo apt-get install mlocate

echo -e "\e[1m> Créer le groupe $user_ssh.\e[0m"
sudo addgroup $user_ssh

echo -e "\e[1m> Créer l'user $user_ssh.\e[0m"
sudo useradd $user_ssh --gid $user_ssh -m --shell /bin/bash

echo -e "\e[1m> Copie le squelette de home.\e[0m"
sudo cp -a /etc/skel/. $chroot_dir
sudo chown $user_ssh: -R $chroot_dir
sudo chown root: $chroot_dir

echo -e "\e[1m> Créer les dossiers pour les exe du chroot.\e[0m"
sudo mkdir $chroot_dir/{dev,bin,lib,lib64,proc}

echo -e "\e[1m> Copie des exécutables dans le chroot.\e[0m"

echo -e "\e[1m> Créer un /dev/urandom.\e[0m"
sudo mknod $chroot_dir/dev/urandom c 1 9
sudo chmod 666 $chroot_dir/dev/urandom

echo -e "\e[1m> Copie /dev/null.\e[0m"
sudo cp -a /dev/null $chroot_dir/dev/null

echo -e "\e[1m> Monte les interfaces loadavg et uptime de proc.\e[0m"
sudo touch $chroot_dir/proc/{loadavg,uptime}
# Add these mount to the fstab
echo -e "\n#CI# This 2 mount bind with /proc are for the ssh chroot of the CI" | sudo tee -a /etc/fstab
echo "/proc/loadavg $chroot_dir/proc/loadavg none bind" | sudo tee -a /etc/fstab
echo "/proc/uptime $chroot_dir/proc/uptime none bind" | sudo tee -a /etc/fstab
# Then mount them
sudo mount $chroot_dir/proc/loadavg
sudo mount $chroot_dir/proc/uptime

cp_which () {
	sudo cp -aH `which $1` $chroot_dir/bin/$1
}
locate_and_cp () {
	local path_of_file=$(locate $1 | head -n1)
	sudo cp -aH $path_of_file $chroot_dir/lib/
}

echo -e "\e[1m> Copie les fichiers ld-linux, selon l'arch.\e[0m"
sudo cp -v /lib/ld-linux.so.2 $chroot_dir/lib/
sudo cp -v /lib64/ld-linux-x86-64.so.2 $chroot_dir/lib64/
sudo cp -v /lib/ld-linux-armhf.so.3 $chroot_dir/lib/

echo -e "\e[1m> Met à jour la bdd de locate.\e[0m"
sudo updatedb

echo -e "\e[1m> Copie chaque exécutable nécessaire à analyseCI.sh, ainsi que ses dépendances.\e[0m"
echo -e "\e[1m> bash.\e[0m"
# Pour connaître les dépendances: ldd `which EXE`
cp_which bash
locate_and_cp linux-vdso.so.1
locate_and_cp libncurses.so.5
locate_and_cp libtinfo.so.5
locate_and_cp libtinfo.so.6
locate_and_cp libdl.so.2
locate_and_cp libc.so.6
echo -e "\e[1m> cat.\e[0m"
cp_which cat
locate_and_cp linux-vdso.so.1
locate_and_cp libc.so.6
echo -e "\e[1m> cut.\e[0m"
cp_which cut
locate_and_cp linux-vdso.so.1
locate_and_cp libc.so.6
echo -e "\e[1m> date.\e[0m"
cp_which date
locate_and_cp linux-vdso.so.1
locate_and_cp libc.so.6
echo -e "\e[1m> dirname.\e[0m"
cp_which dirname
locate_and_cp linux-vdso.so.1
locate_and_cp libc.so.6
# echo
echo -e "\e[1m> head.\e[0m"
cp_which head
locate_and_cp linux-vdso.so.1
locate_and_cp libc.so.6
echo -e "\e[1m> grep.\e[0m"
cp_which grep
locate_and_cp linux-vdso.so.1
locate_and_cp libpcre.so.3
locate_and_cp libdl.so.2
locate_and_cp libc.so.6
locate_and_cp libpthread.so.0
echo -e "\e[1m> uptime.\e[0m"
cp_which uptime
locate_and_cp linux-vdso.so.1
locate_and_cp libprocps.so.3
locate_and_cp libprocps.so.6
locate_and_cp libprocps.so.7
locate_and_cp libdl.so.2
locate_and_cp libc.so.6
locate_and_cp libsystemd.so.0
locate_and_cp librt.so.1
locate_and_cp liblzma.so.5
locate_and_cp liblz4.so.1
locate_and_cp libgcrypt.so.20
locate_and_cp libpthread.so.0
locate_and_cp libgcc_s.so.1
locate_and_cp libgpg-error.so.0
echo -e "\e[1m> rsync.\e[0m"
cp_which rsync
locate_and_cp linux-vdso.so.1
locate_and_cp libarmmem.so
locate_and_cp libattr.so.1
locate_and_cp libacl.so.1
locate_and_cp libpopt.so.0
locate_and_cp libc.so.6
echo -e "\e[1m> sed.\e[0m"
cp_which sed
locate_and_cp linux-vdso.so.1
locate_and_cp libacl.so.1
locate_and_cp libselinux.so.1
locate_and_cp libc.so.6
locate_and_cp libattr.so.1
locate_and_cp libpcre.so.3
locate_and_cp libdl.so.2
locate_and_cp libpthread.so.0
echo -e "\e[1m> sleep.\e[0m"
cp_which sleep
locate_and_cp linux-vdso.so.1
locate_and_cp libc.so.6
echo -e "\e[1m> tail.\e[0m"
cp_which tail
locate_and_cp linux-vdso.so.1
locate_and_cp libc.so.6
# test
echo -e "\e[1m> tr.\e[0m"
cp_which tr
locate_and_cp linux-vdso.so.1
locate_and_cp libc.so.6
echo -e "\e[1m> true.\e[0m"
cp_which true
locate_and_cp linux-vdso.so.1
locate_and_cp libc.so.6
echo -e "\e[1m> wc.\e[0m"
cp_which wc
locate_and_cp linux-vdso.so.1
locate_and_cp libc.so.6

sudo git clone https://github.com/YunoHost/CI_package_check "$chroot_dir/CI_package_check"

echo -e "\e[1m> On ajoute le chroot pour l'user.\e[0m"
echo -e "\nMatch User $user_ssh # $user_ssh CI" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tChrootDirectory /home/%u # $user_ssh CI" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tAllowTcpForwarding no # $user_ssh CI" | sudo tee -a /etc/ssh/sshd_config
echo -e "\tX11Forwarding no # $user_ssh CI" | sudo tee -a /etc/ssh/sshd_config

echo -e "\e[1m> Mise en place de la clé ssh.\e[0m"
sudo mkdir $chroot_dir/.ssh
sudo mv "$chroot_dir/CI_package_check/auto_build/official_CI.pub" $chroot_dir/.ssh/authorized_keys
sudo chown $user_ssh: -R $chroot_dir/.ssh/

echo -e "\e[1m> Et bridage de la clé.\e[0m"
sudo sed -i 's/^.*/no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty &/g' $chroot_dir/.ssh/authorized_keys
sudo service ssh reload

# If there's a backup of a previous config file for package check, put it back.
if [ -e "$script_dir/config.backup" ]
then
        sudo mkdir "$chroot_dir/CI_package_check/package_check"
        sudo mv "$script_dir/config.backup" "$chroot_dir/CI_package_check/package_check/config"
fi


echo -e "\e[1m> Installe CI_package_check dans le dossier.\e[0m"
sudo "$chroot_dir/CI_package_check/build_CI.sh"
