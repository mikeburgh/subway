# Subway

Automatically create [Cloudflare Tunnels](https://www.cloudflare.com/products/tunnel/) and/or Caddy Reverse proxy (for local access) for Docker containers.

Inspired by: https://github.com/aschzero/hera

## How It Works

Subway connects to the Docker daemon, and if a container with a `subway.hostname` label is running, started or stopped then subway will update the cloudflared tunnel or caddy configuration accordingly.

Optionally, specify `subway.port` for the port to proxy, if the container only exposes one port this is not required.

It can use either cloudflare tunnels or caddy to expose the containers or both pending on the use case.

### Cloudflare Service
It will create a tunnel called Subway, and for hostnames specified in the label subway.hostname it will create a DNS mapping in the cloudflare DNS to the tunnel UUID.

### Caddy Service
It will create a reverse proxy configuration in caddy for local network access with optional SSL certificate via DNS

## Current Status

It works, but it's rough (it's a bash script!), I built it for personal use, your mileage may vary.

## Configuration

| Enviroment Variables | Function | DEFAULT |
| :---- | --- | --- |
| `SERVICES` | One or more services to enable separated by a comma, eg: 'cloudflare' or 'caddy' or 'cloudflare,caddy' | cloudflare 
| `CADDY_ACME_DNS` | To use DNS rather than the built in caddy HTTP for the SSL challenge. The dns provider and token to use for Caddy [acme_dns](https://caddyserver.com/docs/caddyfile/options#acme-dns). Only cloudflare dns is supported for now, and format is 'cloudflare token' where token is the [auth token](#cloudflare-auth-token) |  
| `CADDY_WILDCARD_DOMAIN` | To use a wild card domain set this to the domain, eg *.example.com Note: must also set CADDY_ACME_DNS to use wildcard domains for SSL |  
| `CONNECT_NETWORKS` | Automatically connect Subway to networks the container maybe on to try and reach the services. Set to true to enable. Note requires read/write access to the docker.sock |  
| `EXTERNAL_SERVICES` | See [external services](#external-services) |  |


## Using with just cloudflare

1. Start Subway:

```bash
docker run \
	--name=Subway
	-v /var/run/docker.sock:/var/run/docker.sock \
	-v '/path/to/data':'/data':'rw' \
	mikeburgh/subway:latest
```

2. On first run check the docker logs for the authorization url, and copy it to a browser to complete authorization.

3. Assign subway.hostname and subway.port (optional, only required if multiple ports exposed on container) labels to containers you want to access via the tunnel and then restart them for Subway to notice the change.

## Using with just caddy

1. Start Subway:

```bash
docker run \
	--name=Subway
	-v /var/run/docker.sock:/var/run/docker.sock \
	-v '/path/to/data':'/data':'rw' \
	-e SERVICES=caddy \
	-e CADDY_ACME_DNS="cloudflare token" \
	mikeburgh/subway:latest
```

2. (optional, only required for dns SSL challenge when sites are not accessable over the internet). To get the value for the token and replace it in the variable above go to https://dash.cloudflare.com/profile/api-tokens and create a custom token with the following settings  
Permissions:
	- Zone - DNS - Edit

	Zone Resources:
	-  Include - Specific Zone - the zone you are using


3. Assign subway.hostname and subway.port (optional, only required if multiple ports exposed on container) labels to containers you want to access via caddy and the reverse proxy and then restart them for Subway to notice the change.


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
-   The domain you select to authorize is the only one you can use in the label subway.hostname.
-   The subway container must be able to communicate with the containers with subway labels, you may need to create a dedicated network for subway and bridge it place Subway and other containers in it.

## Todo

-   Option to expose it's metrics, if hostname on the container
-   Delete dns records of stopped containers (may require functionality from Cloudflare)
-   Better handle if tunnel name exists
-   Expose tunnel name as a docker ENV
-   Support private network routing
- 	Option to configure container for either cloudflare or caddy if both are used
- 	Support EXTERNAL_SERVICES in caddy
-   Support multiple domains (may require multiple tunnels)

## To Build

docker build -t mikeburgh/subway:latest .
