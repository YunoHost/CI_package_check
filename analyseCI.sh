#!/bin/bash

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

# Le premier (et seul) argument du script est l'adresse du dépôt git à tester

echo $1 >> "$script_dir/work_list"	# Ajoute le dépôt à tester à la suite de la liste
APP=$(basename $1)

date
echo "Attente du début du travail"
if ! test -e "$script_dir/logs/$APP.log"
then	# Si c'est la première exécution de ce test, le fichier de log n'existe pas.
	echo "!!! Attention première exécution du test, l'indication de début de travail est faussée..."
fi
while test -e "$script_dir/logs/$APP.log"; do
	sleep 30	# Attend que le log soit supprimé par le script pcheckCI.sh, ce qui indiquera le début du test sur ce package.
	echo -n "."
done
# Cette double boucle permet de ne pas effacer trop tôt le log précédent. Mais seulement pendant le travail de Package_check sur le package concerné.
echo ""
date
echo -e "Package_check est actuellement en train de tester le package"
while ! test -e "$script_dir/logs/$APP.log"; do
	sleep 30	# Attend que le log soit recréé par le script pcheckCI.sh, ce qui indiquera la fin du test sur ce package.
	echo -n "."
done
echo ""
date
echo -ne "Fin du test."

cat "$script_dir/logs/$APP.log"	# Affiche le log dans le CI

if grep "FAIL$" "$script_dir/logs/$APP.log" | grep -v "Package linter" | grep -q "FAIL$"
then	# Cherche dans le résultat final les FAIL pour connaitre le résultat global.
# grep -v "Package linter" est temporaire et permet d'éviter d'afficher un package en erreur si il ne passe pas le test de Package linter
	exit 1	# Si des FAIL sont trouvé, sort en erreur.
else
	exit 0	# Sinon tout les tests ont réussi.
fi
