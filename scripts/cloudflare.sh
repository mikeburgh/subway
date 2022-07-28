#!/bin/bash

#The methods for cloudflare specific setup



#store our pid for cloudflared
pid=0

#write our empty ingress into the file, along with the path to the creds
echo "credentials-file: /data/subway.json
ingress:" > cloudflare_config.yml

#figure out if /data/cert.perm exists or not, if not run login and copy it!
if [[ -f /data/cert.perm ]]
then
	#copy it to where cloudflare expects it
	mkdir /root/.cloudflared
	cp /data/cert.perm /root/.cloudflared/cert.pem 
else
	echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') SUBWAY Loging into cloudflare"
	./cloudflared login
	cp /root/.cloudflared/cert.pem /data/cert.perm
fi 

echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') SUBWAY Creating cloudflare tunnel"
#specify the cred path here!
./cloudflared --cred-file /data/subway.json tunnel create subway || true

#Any external services ?
if [[ $EXTERNAL_SERVICES ]]
then
	echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') SUBWAY Setting up external services supplied via enviroment variable EXTERNAL_SERVICES:"
	echo $EXTERNAL_SERVICES

	#Loop objects, adding dns to the tunnel
	echo $EXTERNAL_SERVICES | jq -c -r '.[].hostname' | while read exhostname; do
		./cloudflared --overwrite-dns tunnel route dns subway $exhostname || true
	done

	#write them into the config file!
	yq e -i ".ingress += $EXTERNAL_SERVICES" cloudflare_config.yml
fi



cloudflaredRemoveContainer() { 
	#delete the hostname if it exists from our file (ignores it if it does not)
	echo " - Removing ${hostname} from cloudflare tunnel"
	yq e -i "del(.ingress[] | select(.hostname == \"$hostname\"))" cloudflare_config.yml
	#todo - Sort out deleting dns records!
}

cloudflaredAddContainer() { 
	echo " - Adding ${hostname} to cloudflare tunnel via service ${service}"
	#update our ingress for the container!
	yq e -i ".ingress += [{\"hostname\": \"$hostname\",\"service\": \"$service\"}]" cloudflare_config.yml
	./cloudflared --overwrite-dns tunnel route dns subway $hostname || true
}

#Start cloudflared, and kill the previous one if exists!
cloudflaredRestart() { 

	#delete our serivce 404 (if we added a new service it gets added to the end, so 404 status is above it)
	yq e -i 'del(.ingress[] | select(.service == "http_status:404"))' cloudflare_config.yml

	#append a 404 service on the end!
	yq e  -i '.ingress += [{"service": "http_status:404"}]' cloudflare_config.yml

	echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') SUBWAY Starting cloudflared with config:"
	yq e 'del(.credentials-file)' cloudflare_config.yml
	./cloudflared tunnel --config cloudflare_config.yml run subway &
    newPid=$!
	if [ $pid != 0 ]
	then
		echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') SUBWAY Stopping old cloudflared.."
		kill $pid
	fi
	pid=$newPid
}
