#!/bin/bash

SNAP="$1"
CMD="`basename $0 | awk -F. '{ print $1 }'`" || exit 1


DOMAINS="director overcloud-controller overcloud-compute1 overcloud-compute2 overcloud-ceph0"

# rollback_env , snapshot_env
echo "CMD=[$CMD] SNAP=[$SNAP]"
[ -z "$CMD" ] && exit 2

if [ -z "$SNAP" ]; then
	SNAP="images_downloaded3"
	echo "WARN: using default snap[$SNAP]"
fi

## ------------- snapshot_list
if [ "$CMD" = "snapshot_list" ]; then
	for L in $DOMAINS; do
		echo $L
		virsh snapshot-list $L --tree
	done
	exit 0
fi


echo "REALLY run [$CMD].[$SNAP] . changes will be LOST"
while [ 1 ]; do
	echo -n "(y/n) ?"; read CH
	[ "x$CH" == "xy" ]  && break
	[ "x$CH" == "xn" ]  && exit
done

## ------------- snapshot_env
if [ "$CMD" = "snapshot_env" ]; then
	if [ -z "$SNAP" ]; then
		echo "usage: $0 CMD SNAPSHOT"
		exit 1
	fi
	set -x
	for L in $DOMAINS; do
		virsh snapshot-create-as --domain $L --name "$SNAP"
	done
	exit
fi
## -------------- rollback_env
if [ "$CMD" = "rollback_env" ]; then
	set -x
	for L in $DOMAINS; do
		virsh destroy $L
		virsh snapshot-revert $L $SNAP
	done
	virsh start director
	exit
fi
