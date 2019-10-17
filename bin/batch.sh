#!/bin/bash
DOMS="$*"

if [ -z "$DOMS" ]; then
	echo "usage: $0 [ controllerX .. ] [ computeX .. ] [ cephX .. ]"
	echo "makke a batch of overcloud vms"
	exit 0
fi

LAST_PORT="$(su - jkrah -c 'vbmc list -f csv -c Port | grep -v Port | sort -n | tail -1')"
echo "LAST_PORT=[$LAST_PORT]"
if [ -z "$LAST_PORT" ]; then
	echo "Frist port.."
	let PORT=6000
else
	let PORT=$LAST_PORT+1 || exit 2
fi
echo "starting at port[$PORT]"
	echo "press enter to build [$DOMS]"
	read CH
#let PORT=6010
export SKIP_PROMPT=y
for DOM in $DOMS; do
	echo "DOM[$D] PORT[$PORT]"
	DISKS="60G"
	if [ ! -z "`echo $DOM | grep ^ceph`" ]; then
	echo "[$DOM] is a ceph.."
	DISKS="60G 20G 20G 20G"
	fi
	echo "DISKS=[$DISKS]"
	/data/nfs/openstack/tripleo/vm/vm-ctl.sh mkdisk $DOM "$DISKS" || exit
	/data/nfs/openstack/tripleo/vm/vm-ctl.sh mkxml $DOM "br5 br6 br7 br4" 16 1700 || exit
	/data/nfs/openstack/tripleo/vm/vm-ctl.sh mkjson $DOM dl380 $PORT br5 || exit
	su - jkrah -c "vbmc add $DOM --port $PORT --username admin --password password --libvirt-uri qemu+ssh://root@dl380/system"
	su - jkrah -c "vbmc start $DOM"
	
	let PORT=$PORT+1
done
	
su - jkrah -c "vbmc list"
