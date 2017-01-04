#!/bin/bash

if [ "$#" -ne 2 ]
then
	echo "Le script prend en argument le package à tester et le nom du test."
	exit 1
fi

milli_sleep=$(head -n20 /dev/urandom | tr -c -d '0-9' | head -c3)       # Prend 3 chiffres aléatoires pour avoir une valeur entre 1 et 999 millisecondes
sleep "0.$milli_sleep"	# Retarde au maximum d'une seconde le démarrage pour éviter des démarrages concurrents.

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

id=$(head -n20 /dev/urandom | tr -c -d 'A-Za-z0-9' | head -c10)	# Défini un id unique pour le test.
# Le premier argument du script est l'adresse du dépôt git à tester
echo "$1;$id;$2" >> "$script_dir/work_list"	# Ajoute le dépôt à tester à la suite de la liste
ARCH="$(echo $(expr match "$2" '.*\((~.*~)\)') | cut -d'(' -f2 | cut -d')' -f1)"	# Isole le nom de l'architecture après le nom du test.
APP_LOG=$(echo "${1#http*://}" | sed 's@/@_@g')$ARCH.log # Supprime http:// ou https:// au début et remplace les / par des _. Ceci sera le fichier de log de l'app.

echo ""
date
echo "Attente du début du travail..."
while true; do	# Boucle infinie.
	if test -e "$script_dir/CI.lock"	# Si le lock du CI est en place, le script pcheckCI a commencé à travailler.
	then
		if [ "$(cat "$script_dir/CI.lock")" = "$id" ]	# Si le fichier CI.lock contient l'id de l'application à tester, le test a débuté.
		then
			break	# Sors de la boucle d'attente
		fi
	fi
	sleep 30
	echo -n "."
done
echo ""
date
echo "Package_check est actuellement en train de tester le package..."
nb_print=0
while ! test -e "$script_dir/logs/$APP_LOG"; do
	sleep 30	# Attend que le log soit recréé par le script pcheckCI.sh, ce qui indiquera la fin du test sur ce package.
	if [ "$nb_print" -gt 1 ]; then
		cat "$script_dir/package_check/Complete.log" | grep ">>.*Test" | sed "1,"$nb_print"d"	# Affiche les titres de test, en supprimant autant de ligne trouvée que de test déjà affichés. Pour afficher seulement les nouveaux tests.
	else
		cat "$script_dir/package_check/Complete.log" | grep ">>.*Test"	# Si il n'y a qu'un seul titre de test trouvé, affiche simplement.
	fi
	nb_print=$(cat "$script_dir/package_check/Complete.log" | grep -c ">>.*Test")	# Compte le nombre de titre de test déjà affichés.
done
echo ""
date
echo -ne "Fin du test."

cat "$script_dir/logs/$APP_LOG"	# Affiche le log dans le CI
echo -n "" > "$script_dir/CI.lock"	# Vide le fichier lock pour indiquer qu'il peux être supprimé. (Ce script n'a pas suffisamment de droit pour supprimer lui-même le fichier.)

if grep "FAIL$" "$script_dir/logs/$APP_LOG" | grep -v "Package linter" | grep -q "FAIL$" || grep "PCHECK_AVORTED" "$script_dir/logs/$APP_LOG"
then	# Cherche dans le résultat final les FAIL pour connaitre le résultat global. Ou PCHECK_AVORTED qui annonce un time out de Package check.
# grep -v "Package linter" est temporaire et permet d'éviter d'afficher un package en erreur si il ne passe pas le test de Package linter
	exit 1	# Si des FAIL sont trouvé, sort en erreur.
elif ! grep "SUCCESS$" "$script_dir/logs/$APP_LOG" | grep -v "Package linter" | grep -q "SUCCESS$"
then    # Si il n'y a aucun SUCCESS à l'exception de Package linter. Aucun test n'a été effectué.
        exit 1
else
	exit 0	# Sinon tout les tests ont réussi.
fi
