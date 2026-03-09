FROM alpine:latest

WORKDIR /usr/src/app

VOLUME [ "/config" ]

RUN apk --no-cache add jq curl

RUN echo "*/10 * * * * /bin/sh /usr/src/app/main.sh" | crontab -

COPY *.sh ./

CMD ["/usr/src/app/entrypoint.sh"]
