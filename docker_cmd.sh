#!/bin/bash

START=FALSE
DOCKER=/usr/bin/docker

if [ x$1 == x'start' ]
then
    START=TRUE
fi

argu=$@
container=""

if [ $START == TRUE ]
then
    /usr/local/bin/dctl clear
    shift
    while [ $# -ne 0 ]
    do
        if [ x$1 == '-a' ] || [ x$1 == '-i' ] || [ x$1 == x'--attach' ] || [ x$1 == x'--interactive' ] || [ x$1 == '-ai' ]
        then
            :;
        elif [ x$1 == x'--checkpoint' ] || [ x$1 == x'--checkpoint-dir' ] || [ x$1 == x'--detach-keys' ]
        then
            shift
        else
            container="$container $1"
        fi
        shift
    done
fi

$DOCKER $argu

if [ $? -eq 0 ] && [ $START == TRUE ] && [ ${#container} -ne 0 ]
then
    /usr/local/bin/dctl recover $container
fi