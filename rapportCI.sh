#!/bin/bash

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

dest=$(grep "dest=" "$script_dir/config" | cut -d= -f2)	# Récupère le destinataire du mail
type_mail=$(grep "type_mail=" "$script_dir/config" | cut -d= -f2)	# Récupère le format du mail
ci_url=$(grep "CI_URL=" "$script_dir/config" | cut -d= -f2)	# Récupère l'adresse du logiciel de CI

mail_md="$script_dir/CR_mail.md"
mail_html="$script_dir/CR_mail.html"

JENKINS_JOB_URL () {
	job_url=https://${ci_url}/job/${job}/lastBuild/console
}

BUILD_JOB_URL () {
	JENKINS_JOB_URL
	job_url=$(echo $job_url | sed 's/ /%20/g')	# Remplace les espaces
	job_url=$(echo $job_url | sed 's/(/%28/g' | sed 's/)/%29/g')	# Remplace les parenthèses
}

echo "## Compte rendu hebdomadaire des tests d'intégration continue." > "$mail_md"

cat << EOF > "$mail_html"	# Écrit le début du mail en html
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
</head>

<body>
<strong><font size="5">
Compte rendu hebdomadaire des tests d'intégration continue.
</font></strong>
<br>
<br>
EOF

while read ligne
do
	if ! grep -q "_complete.log$" <<< "$ligne"	# Ignore les logs "complete", ne traite que les autres fichiers.
	then
		job=$(grep "^-> Test " < "$script_dir/logs/$ligne")	# Récupère le nom du test, ajouté au début du log
		job=${job#-> Test }	# Supprime "-> Test " pour garder uniquement le nom du test
		if echo "$job" | grep -q " (Official)"; then
			echo -n "0." >> "$script_dir/sortliste"	# Préfixe les app officielle de 0
		else
			echo -n "1." >> "$script_dir/sortliste" # Et les autre de 1, pour forcer le tri des apps officielles au début de la liste.
		fi
		echo "$job:$ligne"	>> "$script_dir/sortliste"	# Inscrit dans le fichier temporaire le nom du job suivi du nom du log.
	fi
done <<< "$(ls -1 "$script_dir/logs")"
sort "$script_dir/sortliste" -o "$script_dir/sortliste"	# Tri la liste des apps
sed -i 's/^[0-1].//g' "$script_dir/sortliste"	# Supprime le 0. ou 1. au début de chaque ligne.

while read ligne
do
	job=${ligne%%:*}	# Supprime après : pour garder uniquement le job.
	ligne=${ligne#*:}	# Supprime avant : pour garder uniquement le nom du log.
	global_result=$(grep "FAIL$" "$script_dir/logs/$ligne" | grep -v "Package linter" | grep -c "FAIL$")	# Récupère la sortie du grep pour savoir si des FAIL sont sortis sur le test
	if grep "PCHECK_AVORTED" "$script_dir/logs/$ligne" > /dev/null; then
		global_result=-1	# Indique que package_check a été arrêté par un timeout.
	fi
	results=$(grep "Notes de résultats" "$script_dir/logs/$ligne" -m1 -B30 | grep "FAIL$\|SUCCESS$")	# Isole le premier résultat de test et récupère la liste des tests effectués
	if [ "$global_result" -eq "-1" ]; then
		results="$(echo $results; grep "PCHECK_AVORTED" "$script_dir/logs/$ligne" | cut -d'(' -f 1): FAIL"	# Ajoute l'erreur de timeout aux tests échoués.
	fi
	score=$(grep "Notes de r.*sultats: .*/20" "$script_dir/logs/$ligne" | grep -o "[[:digit:]]\+/20.*")	# Récupère le (ou les) notes de tests
	level=$(tac "$script_dir/logs/$ligne" | grep "Niveau de l'application: " -m1  | cut -d: -f2 | cut -d' ' -f2)

	BUILD_JOB_URL	# Génère l'url du job sur le logiciel de CI
	echo -en "\n### Test [$job]($job_url):" >> "$mail_md"
	echo -n "<br><strong><a href="$job_url">Test $job: </a><font color=" >> "$mail_html"
	if [ "$global_result" -eq 0 ]; then
		echo " **SUCCESS** :white_check_mark:" >> "$mail_md"
		echo "green>SUCCESS" >> "$mail_html"
	else
		echo " **FAIL** :negative_squared_cross_mark:" >> "$mail_md"
		echo "red>FAIL" >> "$mail_html"
	fi
	echo -e "</font>\n</strong>\n<br>" >> "$mail_html"
	results=$(echo "$results" | sed 's/\t//g')	# Efface les tabulations dans les résultats
	results=$(echo "$results" | sed 's/: /&**/g' | sed 's/.*$/&**/g')	# Met en gras le résultat lui-même
	if echo "$results" | grep -q "SUCCESS"; then
		echo "" >> "$mail_md"	# Saut de ligne seulement si il y a des succès.
		echo "<ul>" >> "$mail_html"
		echo "$results" | grep "SUCCESS" | sed 's/^.*/- &/g' >> "$mail_md"	# Ajoute un tiret au début de chaque ligne et affiche les résultats
		echo "$results" | grep "SUCCESS" | sed 's/^.*/<li> &/g' | sed 's/.*$/&<\/li>/g' \
		| sed 's/: \*\*/: <strong>/g' | sed 's@\*\*@</strong>@g' >> "$mail_html"	# Ajoute li et /li au début et à la fin de chaque ligne
		echo "</ul>" >> "$mail_html"
	fi
	if echo "$results" | grep -q "FAIL"; then
		echo "-" >> "$mail_md"  # Ajoute un tiret en lieu de saut de ligne, pour ne pas casser la syntaxe des listes markdown.
		echo "<ul>" >> "$mail_html"	# Saut de ligne seulement si il y a des échecs.
		echo "$results" | grep "FAIL" | sed 's/^.*/- &/g' >> "$mail_md"	# Ajoute un tiret au début de chaque ligne et affiche les résultats
		echo "$results" | grep "FAIL" | sed 's/^.*/<li> &/g' | sed 's/.*$/&<\/li>/g' \
		| sed 's/: \*\*/: <strong>/g' | sed 's@\*\*@</strong>@g' >> "$mail_html"	# Ajoute li et /li au début et à la fin de chaque ligne
		echo "</ul>" >> "$mail_html"
	fi
	echo "" >> "$mail_md"
	if [ -n "$level" ]
	then
		echo -n "Niveau de l'application: " >> "$mail_md"
		echo -n "Niveau de l'application: " >> "$mail_html"
		echo "**$level**" >> "$mail_md"
		echo "<strong>$level</strong><br>" >> "$mail_html"
	else
		while read <&3 linescore
		do
			if test -n "$linescore"
			then
				linescore_note=$(echo $linescore | cut -d'/' -f1)
				echo -n "<font color=" >> "$mail_html"
				if [ "$linescore_note" -le 10 ]; then
					echo -n "red" >> "$mail_html"
				elif [ "$linescore_note" -le 15 ]; then
					echo -n "orange" >> "$mail_html"
				elif [ "$linescore_note" -gt 15 ]; then
					echo -n "green" >> "$mail_html"
				fi
				echo "><strong>$linescore</strong></font><br>" >> "$mail_html"
				echo "**$linescore**" >> "$mail_md"
			fi
		done 3<<< "$(echo "$score")"
	fi
	echo "<br>" >> "$mail_html"
	echo "" >> "$mail_md"
done < "$script_dir/sortliste"	# Reprend à partir de la liste triée.
rm "$script_dir/sortliste"

sed -i 's/.\[\+[[:digit:]]\+m//g' "$mail_md" "$mail_html"	# Supprime les commandes de couleurs et de formatages de texte formé par \e[xxm

echo -e "</body>\n</html>" >> "$mail_html"

if [ "$type_mail" == "markdown" ]
then
	mail="$mail_md"
	type="text/plain; markup=markdown"
else
	mail="$mail_html"
	type="text/html"
fi
mail -a "Content-type: $type" -s "[YunoHost] Rapport hebdomadaire de CI" "$dest" < "$mail"	# Envoi le rapport par mail.
