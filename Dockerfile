ARG GOLANG_VERSION=1.17
ARG ALPINE_VERSION=3.15

#Use a builder to build caddy with the DNS plugin
FROM golang:${GOLANG_VERSION}-alpine${ALPINE_VERSION} as build
ARG GOLANG_VERSION
ARG ALPINE_VERSION

WORKDIR /go/src/github.com/caddyserver/xcaddy/cmd/xcaddy

RUN apk add --no-cache git gcc build-base; \
	go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest;

#this last with can probably be removed, it's temp due to an ambigous import!
RUN  xcaddy build \
	 --output /go/src/github.com/caddyserver/xcaddy/cmd/caddy \
	 --with github.com/caddy-dns/cloudflare \
	 --with github.com/antlr/antlr4=github.com/antlr/antlr4/runtime/Go/antlr@v0.0.0-20220209173558-ad29539cd2e9 

#Final Image
FROM alpine:${ALPINE_VERSION}

ARG GOLANG_VERSION
ARG ALPINE_VERSION

#install tools 
RUN apk add --no-cache ca-certificates curl netcat-openbsd jq yq tzdata bash docker-cli; \
    rm -rf /var/cache/apk/*;

#Expose our ports!
EXPOSE 80 443 

COPY --from=build /go/src/github.com/caddyserver/xcaddy/cmd/caddy /bin/

#fetch latest cloudflared
RUN curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 --output /cloudflared
RUN ["chmod", "+x", "/cloudflared"]

RUN mkdir /data; \ 
	mkdir /scripts


#where caddy stores it's data 
ENV XDG_DATA_HOME /data

COPY entrypoint.sh /
COPY scripts/* /scripts/
RUN ["chmod", "+x", "/entrypoint.sh"]


ENTRYPOINT ["/entrypoint.sh"]

CMD [""]