#!/bin/bash

type_mail=html	# Format du mail à envoyer, html ou markdown
dest=root	# Destinataire du mail. root par défaut pour envoyer à l'admin du serveur.

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

mail_md="$script_dir/CR_mail.md"
mail_html="$script_dir/CR_mail.html"

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
		global_result=$(grep "FAIL$" "$script_dir/logs/$ligne" | grep -v "Package linter" | grep -c "FAIL$")	# Récupère la sortie du grep pour savoir si des FAIL sont sortis sur le test
		if grep "PCHECK_AVORTED" "$script_dir/logs/$ligne" > /dev/null; then
			global_result=-1	# Indique que package_check a été arrêté par un timeout.
		fi
		fail=$(grep "FAIL$" "$script_dir/logs/$ligne" | cut -d ':' -f1)	# Récupère la liste des tests échoués en retirant les FAIL
		if [ "$global_result" -eq "-1" ]; then
			fail=$(echo $fail; grep "PCHECK_AVORTED" "$script_dir/logs/$ligne" | cut -d'(' -f 1)	# Ajoute l'erreur de timeout aux tests échoués.
		fi
		score=$(grep "Notes de r.*sultats: .*/20" "$script_dir/logs/$ligne" | grep -o "[[:digit:]]\+/20.*")	# Récupère le (ou les) notes de tests

		echo -en "\n### Test $job:" >> "$mail_md"
		echo -n "<br><strong>Test $job: <font color=" >> "$mail_html"
		if [ "$global_result" -eq 0 ]; then
			echo " **SUCCESS**" >> "$mail_md"
			echo "green>SUCCESS" >> "$mail_html"
		else
			echo " **FAIL**" >> "$mail_md"
			echo "red>FAIL" >> "$mail_html"
		fi
		echo -e "</font>\n</strong>\n<br>" >> "$mail_html"
		if [ -n "$fail" ]; then
			echo "Erreurs sur:" >> "$mail_md" | tee -a "$mail_html"
			echo "" >> "$mail_md"
			echo "<ul>" >> "$mail_html"
			echo "$fail" | sed 's/^.*/<li> &/g' | sed 's/.*$/&<\/li>/g' >> "$mail_html"	# Ajoute li et /li au début et à la fin de chaque ligne
			echo "$fail" | sed 's/^.*/- &/g' >> "$mail_md"	# Ajoute un tiret au début de chaque ligne
			echo "</ul>" >> "$mail_html"
		fi
		echo "" >> "$mail_md"
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
		echo "<br>" >> "$mail_html"
		echo "" >> "$mail_md"
	fi
done <<< "$(ls -1 "$script_dir/logs")"


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
mail -a "Content-type: $type" -s "Rapport hebdomadaire de CI" "$dest" < "$mail"	# Envoi le rapport par mail.
