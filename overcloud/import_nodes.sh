#!/bin/bash

DOMS="$*"

. ~/stackrc || exit


for DOM in $DOMS; do
set -x
	openstack overcloud node import /data/nfs/openstack/tripleo/vm/ironic/${DOM}.json
set +x
done

set -x
openstack overcloud node introspect --all-manageable --provide
set +x

for DOM in $DOMS; do
	echo $DOM | grep compute && ROLE="compute"
	echo $DOM | grep control && ROLE="control"
	echo $DOM | grep ceph && ROLE="ceph-storage"
	echo "assigning  overcloud node[$DOM] role[$ROLE]"
	if [ ! -z "$ROLE" ]; then
		set -x
		openstack baremetal node set --property capabilities="profile:$ROLE,boot_option:local" $DOM
		[ "$ROLE" = "ceph-storage" ] && openstack baremetal node set --property root_device='{"name": "/dev/vda"}' $DOM
		set +x
	else
		echo "ERR: Cant file role for [$DOM]"
	fi
done

openstack baremetal node list
openstack overcloud profiles list

