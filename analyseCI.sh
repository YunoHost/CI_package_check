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

# Relocalise les logs pour testing et unstable
if echo "$2" | grep -q "(testing)"	# Vérifie si c'est un test testing
then
	APP_LOG=logs_testing/$APP_LOG
elif echo "$2" | grep -q "(unstable)"	# Vérifie si c'est un test unstable
then
	APP_LOG=logs_unstable/$APP_LOG
fi

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
log_line=0
log_cli="$script_dir/package_check/Test_results_cli.log"
while ! test -e "$script_dir/logs/$APP_LOG"; do	# Attend que le log soit recréé par le script pcheckCI.sh, ce qui indiquera la fin du test sur ce package.
	sleep 10	# Actualise toute les 10 secondes
	if [ "$log_line" -eq 0 ]; then
		cat "$log_cli"	# Affiche simplement le log si c'est la première fois
	else
		tail -n +$(( $log_line + 1 )) "$log_cli"	# Affiche le log à partir des lignes déjà affichées.
	fi
	log_line=$(wc -l "$log_cli" | cut -d ' ' -f 1)	# Compte le nombre de lignes du log déjà affichées.
done
echo ""
date
echo "Fin du test."

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
