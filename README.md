# Continuous Integration (CI) with Package check for YunoHost

[YunoHost project](https://yunohost.org/#/)

Small scripts set to interface any continuous integration software with [Package_check](https://github.com/YunoHost/package_check).

## Usage:

Simply indicate in the CI software task the `analyzeCI.sh` script as well as the Git repository to test and a test name.
```bash
/PATH/analyseCI.sh "https://github.com/YunoHost-Apps/APP_ynh" "Test name"
```

## How it works:

`pcheckCI.sh` script is started every 5 minutes by the cron job.
If a Git repository is specified in the `work_list` file, it is tested using Package_check and the repository is removed from the list.

The test result is stored in the `logs` folder.

`analyzeCI.sh` script is used by CI software which monitors Git repositories. When it is launched, it adds the repository to test after the `work_list` file.
It waits for the test of its package, then interprets the result contained in the log to know if the test failed or not.

---
There are two reasons for bypassing the CI software.

- It makes it possible not to be dependent on a single software. In this case, the scripts were designed for Jenkins, but can be used by any software.
- It solves the problem of administrator rights required by certain actions of Package_check. The CI software keeps its normal execution rights, only the `pcheckCI.sh` script is executed with root rights by the cron job.

---
## Utilisation de machines distantes:

To test the packages on various processor architectures, it is possible to use remote SSH machines to run other Package check instances.  
The remote machine must have a functional instance of CI_package_check

To use the architectures, you must first add the name of the architecture to be tested to the name of the test. The name of the test is the 2nd argument to give to `analyzeCI.sh`  
The arguments supported for the architectures are:

- `(~x86-64b~)`
- `(~x86-32b~)`
- `(~ARM~)`
Which gives for example
```bash
/PATH/analyseCI.sh "https://github.com/YunoHost-Apps/APP_ynh" "Test name (~x86-64b~)"
```

Remote machines will be connected via SSH, they will require SSH access with a public key without passphrase.
```
ssh-keygen -t rsa -b 4096 -N "" -f "pcheckCI_key"
ssh-copy-id -i pcheckCI_key.pub login@server
```

The config file must be adapted according to the remote machines used.  
For each architecture to be tested in SSH, you must replace `Instance=LOCAL` by `Instance=SSH` and enter the SSH connection information.
