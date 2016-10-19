#!/bin/bash

# builder 在调用 stack 的 verify image 时会传入如下一些环境变量
# APP_NAME:  应用的名称
# CODEBASE:  应用代码的目录
# CACHE_DIR: build image 可以使用这个目录来缓存build过程中的文件,比如maven的jar包,用来加速整个build流程

set -eo pipefail

on_exit() {
    last_status=$?
    trap '' HUP INT TERM QUIT ABRT EXIT
    local exit_status=0
    if [ "$last_status" != "0" ]; then
        if [ -f "process.log" ]; then
          cat process.log
        fi
        exit_status=1
    fi

    if [ "$LAMBDA_URI" != "" ]; then
        echo "Clean lambda env..."
        lambda deprovision --lambda-uri "$LAMBDA_URI"
        clean_status=$?
        if [ "$clean_status" != "0" ]; then
            echo "Clean lambda env fail"
        else
            echo "Clean lambda env success"
        fi
    fi

    trap - HUP INT TERM QUIT ABRT EXIT
    exit ${exit_status}
}

trap on_exit HUP INT TERM QUIT ABRT EXIT

echo "Launch lambda env..."
LAMBDA_URI=$(lambda provision --build-uri "$BUILD_URI")
echo "Launch lambda success"
cd $CODEBASE
LAMBDA_INFO=$(lambda info --lambda-uri $LAMBDA_URI)
ENDPOINT_HOST=$(echo $LAMBDA_INFO|jq --raw-output '.services.web.endpoint.internal.host')
ENDPOINT_PORT=$(echo $LAMBDA_INFO|jq --raw-output '.services.web.endpoint.internal.port')

echo
echo "Building verify jar..."
ENDPOINT="http://$ENDPOINT_HOST:$ENDPOINT_PORT" GRADLE_USER_HOME="$CACHE_DIR" gradle itest 
echo "Build verify finished"
echo
