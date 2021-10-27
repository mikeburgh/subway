# Subway

Automatically create [Cloudflare Tunnels](https://www.cloudflare.com/products/tunnel/) for Docker containers.

Inspired by: https://github.com/aschzero/hera

## How It Works

Subway connects to the Docker daemon, and if a container with a subway.hostname label is running, started or stopped the tunnel and associated DNS will be updated automatically.

It will create a tunnel called Subway, and for hostnames specified in the label subway.hostname it will create a DNS mapping in the cloudflare DNS to the tunnel UUID.

## Current Status

It works, but it's rough (it's a bash script!), I built it for personal use, your mileage may vary.

## Using

1. Start Subway:

```bash
docker run \
	--name=Subway
	-v /var/run/docker.sock:/var/run/docker.sock \
	-v '/path/to/data':'/data':'rw' \
	mikeburgh/subway:latest
```

2. On first run check the docker logs for the authorization url, and copy it to a browser to complete authorization.

3. Assign subway.hostname and subway.port labels to containers you want to access via the tunnel and then restart them for Subway to notice the change.

## External Services

If you have other services outside of docker containers, Subway can manage those provided it can access the service.

To add an extra service, use the EXTERNAL_SERVICES environment variable with a JSON array of hostname and service definitions, eg:

```json
[
	{ "hostname": "site1.example.com", "service": "http://10.1.1.1:8080" },
	{ "hostname": "site2.example.com", "service": "http://10.1.1.2:8080" }
]
```

The JSON also supports originRequest configuration as detailed in [Advanced Configuration](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/configuration/configuration-file/ingress#advanced-configurations)

For example:

```json
[{ "hostname": "site3.example.com", "service": "http://10.1.1.3:8080", "originRequest": { "noTLSVerify": true, "httpHostHeader": "another-site.example.com" } }]
```

An example of running Subway with two external services configured

```bash
docker run \
	--name=Subway
	-v /var/run/docker.sock:/var/run/docker.sock \
	-v '/path/to/data':'/data':'rw' \
	-e 'EXTERNAL_SERVICES'='[{ "hostname": "site1.example.com", "service": "http://10.1.1.1:8080" },{ "hostname": "site2.example.com", "service": "http://10.1.1.2:8080" }]'
	mikeburgh/subway:latest
```

## Important notes

-   Docker.sock is required so it can watch for changes
-   Data volume is required to persist authorization
-   The domain you select to authorize is the only one you can use in the label.hostnames.
-   The subway container must be able to communicate with the containers with subway labels, you may need to create a dedicated network for subway and bridge it place Subway and other containers in it.

## Todo

-   Option to expose it's metrics, if hostname on the container
-   Delete dns records of stopped containers (may require functionality from Cloudflare)
-   Better handle if tunnel name exists
-   Expose tunnel name as a docker ENV
-   Support private network routing
-   Restart cloudflared if it stops
-   Support multiple domains (may require multiple tunnels)

## To Build

docker build -t mikeburgh/subway:latest .
