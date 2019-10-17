#!/bin/bash

BASE=~/overcloudrc

USER="$1"
PASS="$2"
PROJ="$3"

if [ -z "$PROJ" ]; then
	echo "usage: $0 USERNAME PASSWD PROJECT"
	exit 1
fi

SED=""
SED="$SED s/\(OS_USERNAME=\)\(.*\)/\1${USER}/g;"
SED="$SED s/\(OS_PASSWORD=\)\(.*\)/\1${PASS}/g;"
SED="$SED s/\(OS_PROJECT_NAME=\)\(.*\)/\1${PROJ}/g;"

cat $BASE | sed -e "${SED}"
echo 'export PS1="($OS_USERNAME.$OS_PROJECT_NAME)[\u@\h \W]\\$ "'

