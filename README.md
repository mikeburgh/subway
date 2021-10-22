# Subway

Automatically create [Cloudflare Tunnels](https://www.cloudflare.com/products/tunnel/) for Docker containers.

Inspried by: https://github.com/aschzero/hera

## How It Works

Subway connects to the Docker daemon, and if a container with a subway.hostname label is running, started or stopped the tunnel and associated DNS will be updated automatically.

It will create a tunnel called Subway, and for hostnames specified in the label subway.hostname it will create a DNS mapping in the cloudflare DNS to the tunnel UUID.

## Curent Status

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

## Important notes

-   Docker.sock is required so it can watch for changes
-   Data volume is required to persist authorization
-   The domain you select to authorize is the only one you can use in the label.hostnames.
-   The subway container must be able to communicate with the containers with subway labels, you may need to create a dedicated network for subway and bridge it place Subway and other containers in it.

## Todo

-   Echo lines to match cloudflared format (2021-10-21T22:43:53Z INF )
-   Option to expose it's metrics, if hostname on the container
-   Delete dns records of stopped containers (may require functionality from Cloudflare)
-   Better handle if tunnel name exists
-   Expose tunnel name as a docker ENV
-   Add a way to pass in manual ingress mappings outside of docker!
-   Support private network routing
-   Restart cloudflared if it stops
-   Support multiple domains (may require multiple tunnels)

## To Build

docker build -t mikeburgh/subway:latest .
