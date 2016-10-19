FROM hub.deepi.cn/gradle:0.1

RUN apk add --no-cache --update git

ENTRYPOINT ["./build.sh"]

# 由于需要在 build 中将应用代码构建为一个 docker image，因此需要在 docker container 中
# 提供 docker 的客户端，并通过 -v /var/run/docker.sock:/var/run/docker.sock 的方式运行
# host 所提供的 docker
ENV DOCKER_BUCKET get.docker.com
ENV DOCKER_VERSION 1.9.1
RUN curl -sjkSL "https://${DOCKER_BUCKET}/builds/Linux/x86_64/docker-$DOCKER_VERSION" -o /usr/bin/docker \
	&& chmod +x /usr/bin/docker

ADD build.sh build.sh
RUN chmod a+x build.sh