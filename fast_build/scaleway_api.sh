#/bin/bash

token=TOKEN_SCALEWAY

#Serveur de base: VC1S Jessie
server_id=SERVER_ID

SERVER_STATUS () {
		# Surveille l'état du serveur
		curl -sS \
		-H "X-Auth-Token: $token" \
		-H "Content-Type: application/json" \
		https://api.cloud.online.net/servers/$server_id \
		| json_pp \
		| grep "\"state\"" | cut -d '"' -f 4
		# json_pp permet de mettre en forme le json en sortie de curl
}

SERVER_CHECK_STATUS () {
	server_state=-1
	sleep 2
	while [ $server_state -ne 0 ] && [ $server_state -ne 1 ]
	do
		# Surveille l'état du serveur
		server_state=$(SERVER_STATUS)
		# json_pp permet de mettre en forme le json en sortie de curl
		echo "> $server_state"
		if [ "$server_state" = "running" ]; then
			server_state=1
			echo -e "\e[1m>> Le serveur a démarré\e[0m"
		elif [ "$server_state" = "stopped" ]; then
			server_state=0
			echo -e "\e[1m>> Le serveur est arrêté\e[0m"
		else
			server_state=-1
			sleep 30
		fi
	done
}

SERVER_START () {
	server_state=$(SERVER_STATUS)
	if [ "$server_state" = "running" ]; then
		echo -e "\e[1m>> Le serveur est déjà démarré\e[0m"
	else
		SERVER_CHECK_STATUS
		echo -e "\e[1m> Démarrage du serveur\e[0m"
		curl -sS \
		-H "X-Auth-Token: $token" \
		-H "Content-Type: application/json" \
		https://api.cloud.online.net/servers/$server_id/action \
		-d '{"action": "poweron"}' \
		| json_pp

		SERVER_CHECK_STATUS
	fi
}

SERVER_STOP () {
	server_state=$(SERVER_STATUS)
	if [ "$server_state" = "stopped" ]; then
		echo -e "\e[1m>> Le serveur est déjà arrêté\e[0m"
	else
		SERVER_CHECK_STATUS
		echo -e "\e[1m> Arrêt du serveur\e[0m"
		curl -sS \
		-H "X-Auth-Token: $token" \
		-H "Content-Type: application/json" \
		https://api.cloud.online.net/servers/$server_id/action \
		-d '{"action": "poweroff"}' \
		| json_pp

		SERVER_CHECK_STATUS
	fi
}

if [ "$1" = "start" ]
then
	SERVER_START
elif [ "$1" = "stop" ]
then
	SERVER_STOP
elif [ "$1" = "status" ]
then
	SERVER_STATUS
fi
