FROM hub.deepi.cn/gradle:0.1

RUN apk --update add gcc jq

ENTRYPOINT ["verify.sh"]

RUN curl -sjkSL "https://github.com/tw-cde/cde-client-binary/releases/download/0.1.5/lambda" -o /bin/lambda

COPY rootfs /

RUN chmod -R +x /bin/

