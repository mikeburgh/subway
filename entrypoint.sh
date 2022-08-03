#!/bin/bash


#get our container ID, used if we add this container to networks to try and connect to labeled containers
containerID=$(basename $(cat /proc/1/cpuset))

#lower case it!
SERVICES="${SERVICES,,}"

#figure out our services (default if not set is just cloudflare!)
if [[ "$SERVICES" == *"caddy"* ]]
then
	caddy=1
	echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') SUBWAY setting up service: caddy"
	. ./services/caddy.sh
fi

if [[ "$SERVICES" == *"cloudflare"* || -z "$SERVICES" ]]
then
	cloudflare=1
	echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') SUBWAY setting up service: cloudflare"
	. ./services/cloudflare.sh
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
	read hostname name network ports labels< <(echo $(echo ${inspect} | jq --raw-output '.[0] | .Name as $name | .NetworkSettings as $network | .Config.ExposedPorts as $ports | .Config.Labels | . as $labels | to_entries[] | select(.key == "subway.hostname") | "\(.value) \($name) \($network) \($ports) \($labels)"'))
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
			if [[ $(echo ${ports} | jq length) -eq "1" ]]
			then 
				#Container has a single port, we can use it!
				portString=$(echo ${ports} | jq --raw-output 'to_entries[0] | .key')
				#gets the port up to the / format is 8080/tcp so this drops the /tcp 
				port=${portString%/*}
				echo " - subway.port not specified, using single port container exposes: ${port}"
			else	
				echo " - subway.port not specified, multiple ports exposed on container, specify the port using the label subway.port, ignorning"
				return 0
			fi
		else
			echo " - subway.port specified: ${port}"
		fi

		service="" #set up our scopped variable!
		if [[ $port != '' ]]
		then
			network=$network checkContainerAccess
			if [[ $service == "" && $CONNECT_NETWORKS ]]
			then
				#it was empty, but we are allowed to connect networks
				echo " - Failed to connect, connecting to container networks and trying again"

				while read -r netID; do
					docker network connect $netID $containerID
				done< <(echo ${network} | jq --raw-output '.Networks | .[].NetworkID' )

				#try again
				network=$network checkContainerAccess
			fi
		fi

		#if we connected, we can then setup a tunnel for it, so add it to the hostnames!
		if [[ $service != "" ]]
		then
			hostname=$hostname service=$service addContainer
			return 1
		else
			echo " - Failed to connect, ignoring"
		fi
	fi

	return 0
}

##call this like network={docker json network spec} checkContainerAccess
#Will try and access the container via any of the networks and if successfull return the service url
checkContainerAccess() { 

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
			return
		fi
	done< <(echo ${network} | jq --raw-output '.Networks | .[].IPAddress' )

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
