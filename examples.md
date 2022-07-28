

docker run --name=SubwayTest --net hera --rm -e SERVICES=caddy -v /var/run/docker.sock:/var/run/docker.sock -v '/home/mike/Dev/subway/data':'/data':'rw' mikeburgh/subway:test


docker run --name=SubwayTest --net hera --rm -e CADDY_ACME_DNS="cloudflare hhxN_glh7lqpvGfEVfIFbYEpQz73A4aLX8vCjO4o" -e CADDY_WILDCARD_DOMAIN="*.recut.dev" -e SERVICES=caddy -v /var/run/docker.sock:/var/run/docker.sock -v '/home/mike/Dev/subway/data':'/data':'rw' mikeburgh/subway:test