#!/bin/bash
# ------------------------------
abort()
{
	echo "$0: abort ($*)"
	exit 1
}
# ------------------------------
prompt()
{
	echo -n "Proceed: $* (y/N) ?"
	[ -z "$SKIP_PROMPT" ] || return
	read CH
	[ "x$CH" = "xy" ] || abort "user cancelled"
}
# ------------------------------
usage()
{
	echo "usage:  $0 CMD [ DOMAIN ] [ XTRA_ARGS.. ]"
	echo "CMDs = (list,mkdisk,mkxml,mkiro)"
	exit 1
}
# ------------------------------

#cd `dirname $0`/.. || abort "cd err"
# cd `dirname $0` || abort "cd err"
BASEDIR="`( cd $(dirname $0)/.. && pwd )`"
echo "BASEDIR=[$BASEDIR]"
. ${BASEDIR}/bin/prompt.inc || exit 1


XML_DIR="$BASEDIR/data/xml"
IRO_DIR="$BASEDIR/data/json"
IMG_DIR=/var/lib/libvirt/images

[ -d "$XML_DIR" ] || abort "$XML_DIR dir err"
[ -d "$IRO_DIR" ] || abort "$IRO_DIR dir err"
[ -d "$IMG_DIR" ] || abort "$IMD_DIR dir err"

CMD="$1"
DOM="$2"
[ -z "$CMD" ] && usage
# ------------------------------
if [ "$CMD" = "list" ]; then
	if [ -z "$DOM" ]; then
		ls -1rt $IMG_DIR/*_disk*.*
		ls -1rt $XML_DIR/*.xml
		ls -1rt $IRO_DIR/*.json
	else
		ls -1rt $IMG_DIR/${DOM}_disk*.*
		ls -1rt $XML_DIR/$DOM.xml
		ls -1rt $IRO_DIR/$DOM.json
	fi
	exit 0
fi
[ -z "$DOM" ] && usage
# ------------------------------
gen_disk_names()
{
	let C=0
	for D in $DISKS; do
		echo "${DOM}_disk${C}.qcow2|$D"
		let C=$C+1
	done
}
# ------------------------------
if [ "$CMD" = "mkdisk" ]; then
	DISKS="$3"
	echo "..mkdisk [$DOM] [$DISKS]"
	# [ -z "$DISKS" ] && DISKS="40"
	if [ -z "$DISKS" ]; then
		echo "usage: $0 mkdisk $DOM \"size1 size2 ..\""
		exit 0
	fi
	## check for existing disks
	for DNAME in `gen_disk_names | awk -F\| '{ print $1 }'`; do
		ls -l "$IMG_DIR/$DNAME" 2> /dev/null && abort "Image file already exists"
		echo "$IMG_DIR/$DNAME does not exist.. OK"
	done


	gen_disk_names | while read DISK; do
		DNAME="`echo $DISK | awk -F\| '{ print $1 }'`"
		DSIZE="`echo $DISK | awk -F\| '{ print $2 }'`"
		echo ".. qemu-img create -f qcow2 -o preallocation=metadata $IMG_DIR/$DNAME $DSIZE"
	done

	prompt "create disks"

	# mk new disk-set
	gen_disk_names | while read DISK; do
		DNAME="`echo $DISK | awk -F\| '{ print $1 }'`"
		DSIZE="`echo $DISK | awk -F\| '{ print $2 }'`"
		set -x
		qemu-img create -f qcow2 -o preallocation=metadata $IMG_DIR/$DNAME $DSIZE || abort "disk err"
		set +x
	done



	exit 0
fi
# ------------------------------
gen_nic_args()
{
	for D in $NICS; do
		echo -n "--network=bridge=$D "
	done
	[ -z "$NICS" ] || echo
}
gen_disk_args()
{
	for DISK in $DISKS; do
		echo -n "--disk path=$DISK,device=disk,bus=virtio,format=qcow2 "
	done
	[ -z "$DISKS" ] || echo
}
# ------------------------------
if [ "$CMD" = "mkxml" ]; then
	NICS="$3"
	CPUS="$4"
	RAM="$5"
	
	echo "mkxml [$DOM] NICS[$NICS] CPU[$CPUS] RAM[$RAM]"
	if [ -z "$NICS" ] || [ -z "$CPUS" ] || [ -z "$RAM" ]; then 
		echo "usage: $0 mkxml $DOM \"nic_br1 nic_br2 ..\" \"CPUS\" \"RAM\""
		exit 0
	fi
	ls -l "$XML_DIR/${DOM}.xml" 2> /dev/null && abort "xml exists"
	 virsh dominfo --domain $DOM  2> /dev/null && abort "domain exists"
	DISKS="`ls -1 $IMG_DIR/${DOM}_disk*.*`"
	[ -z "$DISKS" ] && abort "Need disks first" 
	NIC_ARGS="`gen_nic_args`"
	DISK_ARGS="`gen_disk_args`"

	echo "NIC: $NIC_ARGS"
	echo "DISK: $DISK_ARGS"
	echo "virt-install --os-variant rhel7 --noautoconsole --vnc --cpu host,+vmx --dry-run --print-xml \
	$NIC_ARGS \
	$DISK_ARGS  \
	--name $DOM --ram $RAM --vcpus $CPUS > $XML_DIR/${DOM}.xml"

	prompt "virt install"

	virt-install --os-variant rhel7 --noautoconsole --vnc --cpu host,+vmx --dry-run --print-xml \
	$NIC_ARGS \
	$DISK_ARGS  \
	--name $DOM --ram $RAM --vcpus $CPUS > $XML_DIR/${DOM}.xml || abort "virt install err"
	virsh define --file $XML_DIR/${DOM}.xml || abort "virsh define err"
	
	exit 0
fi
# ------------------------------
if [ "$CMD" = "mkjson" ]; then

	IRON_TEMPLATE="$BASEDIR/bin/ironic-node.json"
	[ -f "$IRON_TEMPLATE" ] || abort "cant find template [$IRON_TEMPLATE]"
	[ -f "$IRO_DIR/${DOM}.json" ] && abort "$IRO_DIR/${DOM}.json] alread exists"

	HOST="$3"
	PORT="$4"
	PXE_NIC="$5"

	echo "mkjson [$DOM] PORT[$PORT] PXE_NIC[$PXE_NIC]"
	# [ -z "$PORT" ] && PORT=6000
	# [ -z "$PXE_NIC" ] && PXE_NIC=br5
	if [ -z "$PORT" ] || [ -z "$PXE_NIC" ]; then
		echo "usage: $0 mkjson $DOM \"IPMI_HOST\" \"IPMP_PORT\"  \"PXE_NIC\""
		exit 0
	fi
	virsh dominfo  --domain $DOM > /dev/null || abort "Cant find domain[$DOM]"
	MAC="`virsh domiflist --domain $DOM | grep $PXE_NIC | awk '{ print $NF }'`"
	[ -z "$MAC" ] && abort "Cound not get MAC for [$PXE_NIC]"
	echo "MAC=$MAC"

	cat $IRON_TEMPLATE |  sed -e "s/__MAC__/$MAC/g; s/__NAME__/$DOM/g; s/__HOST__/$HOST/g; s/__PORT__/$PORT/g" 
	prompt "Create json"
	cat $IRON_TEMPLATE |  sed -e "s/__MAC__/$MAC/g; s/__NAME__/$DOM/g; s/__HOST__/$HOST/g; s/__PORT__/$PORT/g" > $IRO_DIR/${DOM}.json
	ls -l $IRO_DIR/${DOM}.json || abort "file err"

	echo ".."
	exit 0
fi
# ------------------------------
