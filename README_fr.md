# Intégration Continue (CI) avec Package check pour YunoHost

[YunoHost project](https://yunohost.org/#/)

Petit ensemble de script pour interfacer tout logiciel d'intégration continue avec [Package_check](https://github.com/YunoHost/package_check).

## Usage :

Indiquer simplement dans la tâche du logiciel de CI le script `analyseCI.sh` ainsi que le dépôt Git à tester et le nom du test.
```bash
/PATH/analyseCI.sh "https://github.com/YunoHost-Apps/APP_ynh" "Nom du test"
```

## Fonctionnement :

Le script `pcheckCI.sh` est lancé toutes les 5 minutes par la tâche cron.  
Si un dépôt Git est indiqué dans le fichier `work_list`, il est testé à l'aide de Package_check et le dépôt est retiré de la liste.

Le résultat du test est stocké dans le dossier `logs`.

Le script `analyseCI.sh` est utilisé par le logiciel de CI qui surveille les dépôts Git. Lorsqu'il est lancé, il ajoute le dépôt à tester à la suite du fichier `work_list`.  
Il attend le test de son package, puis interprète le résultat contenu dans le log pour savoir si le test à échoué ou non.

---
Ce contournement du logiciel de CI à deux raisons d'être.  

- D'une part, il permet de ne pas être dépendant d'un seul logiciel. En l'occurence, les scripts ont été conçus pour Jenkins, mais peuvent être utilisé par n'importe quel logiciel.
- D'autre part, il résoud le problème des droits administrateurs nécessaires pour certaines actions de Package_check. Le logiciel de CI garde ses droits d'exécution normaux, seul le script `pcheckCI.sh` est exécuté avec les droits root par la tâche cron.

---
## Utilisation de machines distantes :

Pour tester les packages sur diverses architectures processeur, il est possible d'utiliser des machines distantes en SSH pour exécuter d'autres instance de Package check.
La machine distante doit disposer d'une instance fonctionnelle de CI_package_check

Pour utiliser les architectures il faut tout d'abord ajouter au nom du test le nom de l'architecture à tester. Le nom du test est le 2e argument à donner à `analyseCI.sh`  
Les arguments supportés pour les architectures sont :

- `(~x86-64b~)`
- `(~x86-32b~)`
- `(~ARM~)`
Ce qui donne par exemple
```bash
/PATH/analyseCI.sh "https://github.com/YunoHost-Apps/APP_ynh" "Nom du test (~x86-64b~)"
```

Les machines distantes seront utilisées en SSH, elles nécessiteront un accès SSH avec une clé publique sans passphrase.
```
ssh-keygen -t rsa -b 4096 -N "" -f "pcheckCI_key"
ssh-copy-id -i pcheckCI_key.pub login@server
```

Le fichier de config doit être adapté selon les machines distantes utilisées.  
Pour chaque architecture à tester en SSH, il faut remplacer `Instance=LOCAL` par `Instance=SSH` et renseigner les informations de connexion SSH.
