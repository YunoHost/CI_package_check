Intégration Continue (CI) avec Package check pour YunoHost
==================

[Yunohost project](https://yunohost.org/#/)

Ensemble de script pour interfacer tout logiciel d'intégration continue avec [Package check](https://github.com/YunoHost/package_check).

## Usage
Indiquer simplement dans la tâche du logiciel de CI le script `analyseCI.sh` ainsi que le dépôt git à tester et le nom du test.
```bash
/PATH/analyseCI.sh "https://github.com/YunoHost-Apps/APP_ynh" "Nom du test"
```
