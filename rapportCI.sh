#!/bin/bash

#=================================================
# Grab the script directory
#=================================================

if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

#=================================================
# Get variables
#=================================================

# Get the mail recipient
recipient=$(grep "dest=" "$script_dir/config" | cut --delimiter='=' --fields=2)
# Get the type of mail to send, html or markdown
type_mail=$(grep "type_mail=" "$script_dir/config" | cut --delimiter='=' --fields=2)
# Get the url of the official CI
ci_url=$(grep "CI_URL=" "$script_dir/config" | cut --delimiter='=' --fields=2)

mail_md="$script_dir/CR_mail.md"
mail_html="$script_dir/CR_mail.html"

#=================================================
# Find all apps by their logs
#=================================================

# List all log files in logs dir
while read line
do
	# Ignore all complete logs
	if ! grep --quiet "_complete.log$" <<< "$line"
	then

		# Find the name of the job for this log
		job=$(grep "^-> Test " "$script_dir/logs/$line")
		# Remove "-> Test " for keep only the name of the job
		job=${job#-> Test }

		# Prefix an official apps by 0, and a community by 1. To sort them after
		if echo "$job" | grep --quiet " (Official)"; then
			echo -n "0." >> "$script_dir/sortlist"
		else
			echo -n "1." >> "$script_dir/sortlist"
		fi
		# Add the job name and the log file. Just after the number (0 or 1)
		echo "$job:$line"	>> "$script_dir/sortlist"
	fi
done <<< "$(ls -1 "$script_dir/logs")"

# Sort the list of application, and place the officials apps in first
sort "$script_dir/sortlist" --output="$script_dir/sortlist"
# Then remove the 0 or 1 at the beginning of each line.
sed --in-place 's/^[0-1].//g' "$script_dir/sortlist"

#=================================================
# Give an headline to the message
#=================================================

# Headline for markdown
echo "## Compte rendu hebdomadaire des tests d'intégration continue." > "$mail_md"

# And for html
cat << EOF > "$mail_html"
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

#=================================================
# Build the url of a job
#=================================================

JENKINS_JOB_URL () {
	job_url=https://${ci_url}/job/${job}/lastBuild/console
}

BUILD_JOB_URL () {
	# Build the url of a job

	JENKINS_JOB_URL
	job_url=$(echo $job_url | sed 's/ /%20/g')	# Remplace les espaces
	job_url=$(echo $job_url | sed 's/(/%28/g' | sed 's/)/%29/g')	# Remplace les parenthèses
}

#=================================================
# Read each app listed before
#=================================================

while read line
do
	# Get the job
	job=${line%%:*}
	# Then get the name of the log
	logfile="$script_dir/logs/${line#*:}"

	# Check if at least one test have failed (Except Package linter)
	global_result=$(grep "FAIL$" "$logfile" | grep --invert-match "Package linter" | grep --count "FAIL$")

	# Find the results of tests, just before the level
	results=$(grep "Level of this application:" "$logfile" --max-count=1 --before-context=20 | grep "FAIL$\|SUCCESS$")

	# Check if package check have been aborted before it ends its job
	if grep --quiet "PCHECK_AVORTED" "$logfile"
	then
		# Add this timeout error to the other errors
		results="$(echo $results; grep "PCHECK_AVORTED" "$logfile" | cut --delimiter='(' --fields=1): FAIL"
		global_result=1
	fi

	# Find the last level indication and get only the level itself
	level=$(tac "$logfile" | grep "Level of this application: " --max-count=1  | cut --delimiter=: --fields=2 | cut --delimiter=' ' --fields=2)

	# Build the url of the job
	BUILD_JOB_URL

	# Print the name of the job, and its url into the mail
	echo -en "\n### Test [$job]($job_url):" >> "$mail_md"
	echo -n "<br><strong><a href="$job_url">Test $job: </a><font color=" >> "$mail_html"

	# Print the global result into the mail
	if [ "$global_result" -eq 0 ]; then
		echo " **SUCCESS** :white_check_mark:" >> "$mail_md"
		echo "green>SUCCESS" >> "$mail_html"
	else
		echo " **FAIL** :negative_squared_cross_mark:" >> "$mail_md"
		echo "red>FAIL" >> "$mail_html"
	fi
	echo -e "</font>\n</strong>\n<br>" >> "$mail_html"

	# Remove all tabs in the results
	results=$(echo "$results" | sed 's/\t//g')
	# And put the results themselves in bold
	results=$(echo "$results" | sed 's/: /&**/g' | sed 's/.*$/&**/g')

	# Print SUCCESS results
	if echo "$results" | grep --quiet "SUCCESS"
	then
		echo "" >> "$mail_md"
		echo "<ul>" >> "$mail_html"

		# Print all SUCCESS results and prefix them by a -
		echo "$results" | grep "SUCCESS" | sed 's/^.*/- &/g' >> "$mail_md"
		# Or a 'li' tag
		echo "$results" | grep "SUCCESS" | sed 's/^.*/<li> &/g' | sed 's/.*$/&<\/li>/g' \
		| sed 's/: \*\*/: <strong>/g' | sed 's@\*\*@</strong>@g' >> "$mail_html"
		echo "</ul>" >> "$mail_html"
	fi

	# Print FAIL results
	if echo "$results" | grep --quiet "FAIL"
	then
		echo "-" >> "$mail_md"
		echo "<ul>" >> "$mail_html"

		# Print all FAIL results and prefix them by a -
		echo "$results" | grep "FAIL" | sed 's/^.*/- &/g' >> "$mail_md"
		# Or a 'li' tag
		echo "$results" | grep "FAIL" | sed 's/^.*/<li> &/g' | sed 's/.*$/&<\/li>/g' \
		| sed 's/: \*\*/: <strong>/g' | sed 's@\*\*@</strong>@g' >> "$mail_html"
		echo "</ul>" >> "$mail_html"
	fi

	# Print the global level
	echo "" >> "$mail_md"
	if [ -n "$level" ]
	then
		echo -n "Niveau de l'application: " >> "$mail_md"
		echo -n "Niveau de l'application: " >> "$mail_html"

		echo "**$level**" >> "$mail_md"
		echo "<strong>$level</strong><br>" >> "$mail_html"
	fi

	# Finish the paragraph for this app
	echo "<br>" >> "$mail_html"
	echo "" >> "$mail_md"
done < "$script_dir/sortlist"

# Remove the list before the next execution
rm "$script_dir/sortlist"

# Remove all color marks, identified by \e[xxm
sed --in-place 's/.\[\+[[:digit:]]\+m//g' "$mail_md" "$mail_html"

# Ending the html file
echo -e "</body>\n</html>" >> "$mail_html"

#=================================================
# Send the report by mail
#=================================================

if [ "$type_mail" = "markdown" ]
then
	mail="$mail_md"
	type="text/plain; markup=markdown"
else
	mail="$mail_html"
	type="text/html"
fi
mail -a "Content-type: $type" -s "[YunoHost] Rapport hebdomadaire de CI" "$recipient" < "$mail"	
