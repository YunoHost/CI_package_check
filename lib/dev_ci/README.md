To enable the "send-stuff-to-chroot" mode : 

1) Install `ssh_chroot_dir`: 

```
yunohost app install --force https://github.com/YunoHost-Apps/ssh_chroot_dir_ynh -a "ssh_user=base_user&password=&pub_key=fake_key&size=1G"
```

2) Add corresponding cron job: 

```
# For example in /etc/cron.d/CI_package_check

# Do a scan for new stuff in chroot dirs every minute
*/1 * * * * root "/home/CI_package_check/lib/dev_ci/scan_for_new_jobs_from_chroots.sh" >> "/home/CI_package_check/lib/dev_ci/scan_for_new_jobs_from_chroots.log" 2>&1
```

3) Add users using the `add_new_user_to_dev_ci.sh` script

4) Users should send their stuff using  `send_to_dev_ci.sh`
