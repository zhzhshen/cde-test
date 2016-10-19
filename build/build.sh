#!/bin/bash

# builder 在调用 stack 的 build image 时会传入如下一些环境变量
# APP_NAME:  应用的名称
# CODEBASE:  应用代码的目录
# CACHE_DIR: build image 可以使用这个目录来缓存build过程中的文件,比如maven的jar包,用来加速整个build流程
# IMAGE:     build 成功之后image的名称

set -eo pipefail

on_exit() {
    last_status=$?
    if [ "$last_status" != "0" ]; then
        if [ -f "process.log" ]; then
          cat process.log
        fi

        if [ -n "$MYSQL_CONTAINER" ]; then
            echo
            echo "Cleaning ..."
            docker stop $MYSQL_CONTAINER &>process.log && docker rm $MYSQL_CONTAINER &>process.log
            echo "Cleaning complete"
            echo
        fi
        exit 1;
    else
        if [ -n "$MYSQL_CONTAINER" ]; then
            echo
            echo "Cleaning ..."
            docker stop $MYSQL_CONTAINER &>process.log && docker rm $MYSQL_CONTAINER &>process.log
            echo "Cleaning complete"
            echo
        fi
        exit 0;
    fi
}

trap on_exit HUP INT TERM QUIT ABRT EXIT

# 在将 java 打包为 jar 之前首先执行项目的单元测试，那么在执行测试之前需要安装单元测试所依赖的数据

export DB_MYSQL_USER=mysql
export DB_MYSQL_PASS=mysql
export DB_ON_CREATE_DB=testdb

echo
echo "Launching baking services ..."
MYSQL_CONTAINER=$(docker run -d -P -e MYSQL_USER=$DB_MYSQL_USER -e MYSQL_PASS=$DB_MYSQL_PASS -e ON_CREATE_DB=$DB_ON_CREATE_DB -e MYSQL_ROOT_PASSWORD=$DB_MYSQL_PASS tutum/mysql)
MYSQL_PORT=$(docker inspect -f '{{(index (index .NetworkSettings.Ports "3306/tcp") 0).HostPort}}' ${MYSQL_CONTAINER})
until docker exec $MYSQL_CONTAINER mysql -h127.0.0.1 -P3306 -umysql -pmysql -e "select 1" &>/dev/null ; do
    echo "...."
    sleep 1
done

export DB_HOST=$HOST
export DB_PORT=$MYSQL_PORT

echo "Complete Launching baking services"
echo

cd $CODEBASE

echo
echo "Start migratioin ..."
GRADLE_USER_HOME="$CACHE_DIR" gradle fC fM &> process.log
echo "Migration complete"
echo

echo
echo "Start test ..."
GRADLE_USER_HOME="$CACHE_DIR" gradle clean test -i &> process.log
echo "Test complete"
echo

echo "Start generate standalone ..."
GRADLE_USER_HOME="$CACHE_DIR" gradle standaloneJar &>process.log
echo "Generate standalone Complete"

(cat  <<'EOF'
#!/bin/bash
set -eo pipefail

until nc -z -w 5 $DB_HOST $DB_PORT; do
    echo "...."
    sleep 1
done

export DATABASE="jdbc:mysql://$DB_HOST:$DB_PORT/$DB_ON_CREATE_DB?user=$DB_MYSQL_USER&password=$DB_MYSQL_PASS&allowMultiQueries=true&zeroDateTimeBehavior=convertToNull&createDatabaseIfNotExist=true"
flyway migrate -url="$DATABASE" -locations=filesystem:`pwd`/dbmigration -baselineOnMigrate=true -baselineVersion=0
[ -d `pwd`/initmigration  ] && flyway migrate -url="$DATABASE" -locations=filesystem:`pwd`/initmigration -table="init_version" -baselineOnMigrate=true -baselineVersion=0
java -Xmx450m -XX:+UnlockExperimentalVMOptions -XX:+UseG1GC -jar app-standalone.jar
EOF
) > wrapper.sh

(cat << EOF
FROM hub.deepi.cn/jre-8.66:0.1

CMD ["./wrapper.sh"]

RUN apk --update add tar
RUN mkdir /usr/local/bin/flyway && \
    curl -jksSL https://repo1.maven.org/maven2/org/flywaydb/flyway-commandline/4.0/flyway-commandline-4.0.tar.gz \
    | tar -xzf - -C /usr/local/bin/flyway --strip-components=1
ENV PATH /usr/local/bin/flyway/:\$PATH

ADD build/libs/app-standalone.jar app-standalone.jar

ADD wrapper.sh wrapper.sh
RUN chmod +x wrapper.sh
ENV APP_NAME \$APP_NAME

ADD src/main/resources/db/migration dbmigration
COPY src/main/resources/db/init initmigration

EOF
) > Dockerfile

echo
echo "Building image $IMAGE ..."
docker build -q -t $IMAGE . &>process.log
echo "Building image $IMAGE complete "
echo
