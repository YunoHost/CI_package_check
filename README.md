Intégration Continue (CI) avec Package check pour YunoHost
==================

[Yunohost project](https://yunohost.org/#/)

Petit ensemble de script pour interfacer tout logiciel d'intégration continue avec [Package check](https://github.com/YunoHost/package_check).

## Usage:
Indiquer simplement dans la tâche du logiciel de CI le script `analyseCI.sh` ainsi que le dépôt git à tester et le nom du test.
```bash
/PATH/analyseCI.sh "https://github.com/YunoHost-Apps/APP_ynh" "Nom du test"
```

## Fonctionnement:
Le script `pcheckCI.sh` est lancé toutes les 5 minutes par la tâche cron.  
Si un dépôt git est indiqué dans le fichier `work_list`, il est testé à l'aide de Package_check et le dépôt est retiré de la liste.

Le résultat du test est stocké dans le dossier `logs`.

Le script `analyseCI.sh` est utilisé par le logiciel de CI qui surveille les dépôts git. Lorsqu'il est lancé, il ajoute le dépôt à tester à la suite du fichier `work_list`.  
Il attend le test de son package, puis interprète le résultat contenu dans le log pour savoir si le test à échoué ou non.

---
Ce contournement du logiciel de CI à 2 raison d'être.  

- D'une part, il permet de ne pas être dépendant d'un seul logiciel. En l'occurence, les scripts ont été conçus pour Jenkins, mais peuvent être utilisé par n'importe quel logiciel.
- D'autre part, il résoud le problème des droits administrateurs nécessités par certaines actions de Package_check. Le logiciel de CI garde ses droits d'exécution normaux, seul le script `pcheckCI.sh` est exécuté avec les droits root par la tâche cron.
