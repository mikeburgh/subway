#!/bin/bash




#lower case it!
SERVICES="${SERVICES,,}"

#figure out our services (default if not set is just cloudflare!)
if [[ $SERVICES == "caddy" || $SERVICES == "both" ]]
then
	caddy=1
	echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') SUBWAY setting up service: caddy"
	. ./scripts/caddy.sh
fi

if [[ $SERVICES == "cloudflare" || $SERVICES == "both"  || -z "$SERVICES" ]]
then
	cloudflare=1
	echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') SUBWAY setting up service: cloudflare"
	. ./scripts/cloudflare.sh
fi

##call this like hostname=test.example.com service=10.0.0.x:80 addContainer
#will add the container the appropriate service
addContainer() { 
	[[ -n $cloudflare ]] && hostname=$hostname service=$service cloudflaredAddContainer
	[[ -n $caddy ]] && hostname=$hostname service=$service caddyAddContainer
}

##call this like hostname=test.example.com removeContainer
#will add the container from the appropriate service
removeContainer() {
	[[ -n $cloudflare ]] && hostname=$hostname cloudflaredRemoveContainer
	[[ -n $caddy ]] && hostname=$hostname service=$service caddyRemoveContainer
}

#will start/restart our services on initial load and on changes being detected!
restartServices() { 
	[[ -n $cloudflare ]] && cloudflaredRestart
	[[ -n $caddy ]] && caddyRestart
}

##call this like action=start|stop id=containerID checkContainer
#Get the container config, and if we have labels for subway
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
			hostname=$hostname removeContainer
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
			hostname=$hostname service=$service addContainer
			return 1
		else
			echo " - Failed to connect, ignoring"
		fi
	fi

	return 0
}

echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') SUBWAY Checking existing containers..."

#Get all currently running container IDs
docker ps -q | while read line ; do
    #$line is now the container ID
    #call the update routine to add it (incase it's missed)
    action="start" id=$line checkContainer
done



#Restart them as we have changed now
restartServices

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
		restartServices
	fi

done
