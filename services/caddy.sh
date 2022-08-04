#!/bin/bash

#The methods for caddy specific setup


if [[ $CADDY_ACME_DNS ]]
then
	#create a caddy config with the dns settings, otherwise we let caddy do it using HTTPS
	echo "{
		acme_dns $CADDY_ACME_DNS
	}" > Caddyfile
elif [[ $CADDY_WILDCARD_DOMAIN ]]
then
	echo "Error to use a wildcard domain you need to specify CADDY_ACME_DNS"
	exit 1
else
	echo "" > Caddyfile
fi


#if we have a wild card domain, lets add that now, it wraps all the site configs
if [[ $CADDY_WILDCARD_DOMAIN ]]
then 
	wildcard=1
	echo "$CADDY_WILDCARD_DOMAIN {
    
}" >> Caddyfile
fi


caddyRemoveContainer() { 
	#deletes the lines relating to the hostname from our file!
	echo " - Removing ${hostname} from caddy"

	grep -v "@${hostname}" Caddyfile > temp && mv temp Caddyfile

}

caddyAddContainer() { 
	echo " - Adding ${hostname} to caddy via service ${service}"

	#different configs if we are a wildcard or not
	if [[ -n $wildcard ]]
	then
		#remove the last } (we add it back in) after we add this directive
		head -n -1 Caddyfile > temp && mv temp Caddyfile

		#the comment lines are so we can just remove all matching lines to remove the service in the remove container method
		echo "@$hostname host $hostname
			handle @$hostname {
				reverse_proxy $service #@$hostname
			} #@$hostname
		}">> Caddyfile

	else
		#just add the single site directive to the end, and the comment lines to remove it later!
		echo "$hostname { #@$hostname
			reverse_proxy $service #@$hostname
		} #@$hostname">> Caddyfile
	fi

}

#just does a reload since we are already started!
caddyRestart() {
	caddy reload
}

#process external services
if [[ $EXTERNAL_SERVICES ]]
then
	echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') SUBWAY Setting up external services supplied via enviroment variable EXTERNAL_SERVICES in caddy:"
	echo $EXTERNAL_SERVICES

	#Loop and add them as containers!
	while read -r hostname; do
		read -r service

		hostname=$hostname service=$service caddyAddContainer
		
	done< <(echo ${EXTERNAL_SERVICES} | jq --raw-output '.[] | (.hostname, .service)' )
fi

echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') SUBWAY Starting Caddy"
caddy start
