#!/bin/bash

RECOVER='0'
DOCKER=/usr/bin/docker

if [ x$1 == x'start' ] || [ x$1 != x'start' -a x$1 == x'start']
then
    RECOVER='1'
fi

$DOCKER $@

if [ $RECOVER == '1' ]
then

fi