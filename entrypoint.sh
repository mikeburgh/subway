#!/bin/bash

#store our pid for cloudflared
pid=0

#write our empty ingress into the file, along with the path to the creds
echo "credentials-file: /data/subway.json
ingress:" > config.yml

#figure out if /data/cert.perm exists or not, if not run login and copy it!
if [[ -f /data/cert.perm ]]
then
	#copy it to where cloudflare expects it
	mkdir /root/.cloudflared
	cp /data/cert.perm /root/.cloudflared/cert.pem 
else
	echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') SUBWAY Loging into cloudflared"
	./cloudflared login
	cp /root/.cloudflared/cert.pem /data/cert.perm
fi 

echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') SUBWAY Creating tunnel"
#specify the cred path here!
./cloudflared --cred-file /data/subway.json tunnel create subway || true

#Any external services ?
if [[ $EXTERNAL_SERVICES ]]
then
	echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') SUBWAY Setting up extra services supplied via enviroment variable EXTERNAL_SERVICES:"
	echo $EXTERNAL_SERVICES

	#Loop objects, adding dns to the tunnel
	echo $EXTERNAL_SERVICES | jq -c -r '.[].hostname' | while read exhostname; do
		./cloudflared --overwrite-dns tunnel route dns subway $exhostname || true
	done

	#write them into the config file!
	yq e -i ".ingress += $EXTERNAL_SERVICES" config.yml
fi

##call this like action=start|stop id=containerID checkContainer
#Get the container config, and if we have labels for subway, then manage our config file
checkContainer() { 

	#fetch docker config in json
	inspect=`docker inspect $id`

	#get the hostname and config from our labels from the container!
	read hostname name network labels< <(echo $(echo ${inspect} | jq --raw-output '.[0] | .Name as $name | .NetworkSettings as $network | .Config.Labels | . as $labels | to_entries[] | select(.key == "subway.hostname") | "\(.value) \($name) \($network) \($labels)"'))
	if [[ $hostname ]] 
	then
		echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') SUBWAY Container ${name:1} found with status ${action} and subway.hostname ${hostname}..."

		#if we are stopping we can just check if it exists and delete it if it does!
		if [ $action = "stop" ]
		then
			#delete the hostname if it exists from our file (ignores it if it does not)
			yq e -i "del(.ingress[] | select(.hostname == \"$hostname\"))" config.yml
			#todo - Sort out deleting dns records!
			return 1
		fi

		port=''
		#loop through the labels, getting ones start with subway. and not subway.hostname!
		while read -r key value; do

			#port is special, grab it out!
			if [ $key == 'subway.port' ]
			then
				port=$value
			fi

			#Todo grab other labels, and store them to allow additional configuration!


		done< <(echo ${labels} | jq --raw-output 'to_entries[] | select(.key != "subway.hostname") | select(.key | contains("subway.")) | "\(.key) \(.value)"' )

		#if we did not find a port, see if it only has one exposed in docker, if so use that, otherwise ignore!
		if [[ ! $port ]]
		then
			echo " - No port label found, checking for single exposed port on container.."
			#todo code this!
		fi

		#get each of the networks IP's and see if we can connect to any of them via the port!
		while read -r ip; do
			echo -n " - Checking connection to ${ip}:${port}."

			#loop and sleep to see if it comes up, important since the container could have just started so services might not be ready in time!
			counter=0
			while [  $counter -lt 3  ]; do
				#check and wait 2 seconds for a response, store response or error
				result=`nc -zvw2 ${ip} ${port} 2>&1`
				
				#if we got a zero exit, we found it, stop!
				if [ $? == 0 ]
				then
					break
				fi

				#sleep and try again!
				echo -n "."
				sleep 1
				counter=$((counter+1))
			done

			#echo our last result, it will be success or fail!
			echo " ${result}"
			
			#if counter is not 3, we found it!
			if [ $counter != 3 ]
			then
				#todo fix this to figure out http or https properly!
				service="http://${ip}:${port}"
				break
			fi
		done< <(echo ${network} | jq --raw-output '.Networks | .[].IPAddress' )

		#if we connected, we can then setup a tunnel for it, so add it to the hostnames!
		if [[ -v "service" ]]
		then
			echo " - Adding ${hostname} to tunnel via service ${service}"
			#update our ingress for the container!
			yq e -i ".ingress += [{\"hostname\": \"$hostname\",\"service\": \"$service\"}]" config.yml
			./cloudflared --overwrite-dns tunnel route dns subway $hostname || true
			return 1
		else
			echo " - Failed to connect, not adding to tunnel"
		fi
	fi

	return 0
}

#Start cloudflared, and kill the previous one if exists!
startCloudflared() { 

	#delete our serivce 404 (if we added a new service it gets added to the end, so 404 status is above it)
	yq e -i 'del(.ingress[] | select(.service == "http_status:404"))' config.yml

	#append a 404 service on the end!
	yq e  -i '.ingress += [{"service": "http_status:404"}]' config.yml

	echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') SUBWAY Starting cloudflared with config:"
	yq e 'del(.credentials-file)' config.yml
	./cloudflared tunnel --config config.yml run subway &
    newPid=$!
	if [ $pid != 0 ]
	then
		echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') SUBWAY Stopping old cloudflared.."
		kill $pid
	fi
	pid=$newPid
}

echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') SUBWAY Checking existing containers..."

#Get all currently running container IDs
docker ps -q | while read line ; do
    #$line is now the container ID
    #call the update routine to add it (incase it's missed)
    action="start" id=$line checkContainer
done

#start cloudflared
startCloudflared

echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') SUBWAY Watching for container events... $(date)"
docker events --filter 'event=start' --filter 'event=stop' --format '{{json .}}' | while read event
do

    #grab the ID and status from the event json
	containerID=`echo $event | jq -r '.id'`
    status=`echo $event | jq -r '.status'`

    #Check the container for labels
    action=$status id=$containerID checkContainer
	valResult=$? # '$?' is the return value of the previous command

	#if we had a change made, restarted cloudflared
	if [[ $valResult -eq 1 ]]
	then
		startCloudflared
	fi

done
