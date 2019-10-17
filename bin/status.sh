#!/bin/bash

cd ~ || exit
CMD="`basename $0 | sed -e 's/.sh$//g'`"
echo "CMD=[$CMD]"

SERVERS=".servers.txt"

if [ -f $SERVERS ]; then
	echo "using existing [$SERVERS]"
else
	. ~/stackrc || exit
	echo "updating [$SERVERS].."
set -x
	openstack server list -f csv > $SERVERS
	cat $SERVERS  | awk -F, '{ print $4 "      " $2 }' |  \
		sed -e 's/"//g; s/ctlplane=//g; s/overcloud-//g; s/nova//g; s/-//g' | \
		grep -v ^Networks |  sudo tee -a /etc/hosts
set +x

fi
if [ -f ~/.overcloud.start ]; then
	let STARTSEC=`date -r ~/.overcloud.start +%s`
	echo "install started[`cat ~/.overcloud.start`] ($STARTSEC sec)"
fi

if [ -f ~/.overcloud.end ]; then
	let ENDSEC=`date -r ~/.overcloud.end +%s`
	echo "install ended[`cat ~/.overcloud.end`] ($ENDSEC sec)"
fi

if [ ! -z "$STARTSEC" ] && [ ! -z "$ENDSEC" ]; then
	let SEC=$ENDSEC-$STARTSEC
	let MIN=SEC/60
	echo "Install Time $MIN min ($SEC sec)"

fi

	grep overcloud  $SERVERS | while read LINE; do
		NAME="`echo $LINE |  awk -F, '{ print $2 }' | sed -e 's/"//g; s/overcloud//g; s/nova//g; s/-//g'`"
		IP="`echo $LINE |  awk -F, '{ print $3 }' | sed -e 's/"//g; s/ctlplane=//g; s/-//g'`"
		echo "ssh heat-admin@$NAME"
	done

	
