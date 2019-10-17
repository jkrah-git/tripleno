#!/bin/bash

## openstack server list -f csv -c Name -c Status | grep controller1 | awk -F, '{ print $2 }'
## "ACTIVE"

get_state()
{
  [ -z "$1" ] || openstack server show $1 -c status -f yaml | awk '{ print $2 }'
}

let SLEEP=15
. ~/stackrc || exit 1
for S in $*; do

	set -x
	openstack server stop $S
	set +x
	while [ 1 ]; do
		echo -n "SERV[$S]="
		STATE="`get_state $S`"
		echo "[$STATE]"
		[ "x$STATE" =  "xACTIVE" ] || break
		echo ".. checking again in $SLEEP sec.."
		sleep $SLEEP
	done

done
