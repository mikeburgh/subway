FROM alpine:3.14.2

#install tools 
RUN apk add --no-cache ca-certificates curl netcat-openbsd jq yq bash docker-cli

#fetch latest cloudflared
RUN curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 --output /cloudflared
RUN ["chmod", "+x", "/cloudflared"]

COPY entrypoint.sh /
RUN ["chmod", "+x", "/entrypoint.sh"]

RUN mkdir /data

ENTRYPOINT ["/entrypoint.sh"]

CMD [""]
