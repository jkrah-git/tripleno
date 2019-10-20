#!/bin/bash
BASEDIR="`( cd $(dirname $0)/.. && pwd )`"
echo "BASEDIR=[$BASEDIR]"
. ${BASEDIR}/bin/prompt.inc || exit 1
CHECK="`/usr/bin/whoami`.`/usr/bin/hostname -s`"
[ "x$CHECK" = "xstack.undercloud" ] || abort "CHECK=[$CHECK]"
CONF=~/.overcloud.conf
. $CONF || abort "CONF[$CONF] not found"

. ~stack/stackrc || abort "stackrc err"

STATE=~/.servers.txt
ls $STATE > /dev/null || exit 1

JSON_DIR="${BASEDIR}/data/json"
[ -d "$JSON_DIR" ] || abort "JSON_DIR[$JSON_DIR] err"


####
pingtest()
{
	H="`echo $1 | sed -e 's|overcloud-cephstorage-|cephstorage|g'`"
	ping -w 3 -c 1 $H > /dev/null
	return $?
}
###


startup_list()
{
	. ~stack/stackrc || abort "~stack/overcloudrc err"
	LIST="$*"
	[ -z "$LIST" ] && return
	echo "starting [$LIST].."
	for N in $LIST; do
		pingtest $N && continue
		DOM="`echo $N | sed -e 's|overcloud-cephstorage-|ceph|g'`"
		PORT="$(grep -i Port ${JSON_DIR}/${DOM}.json | awk -F\" '{ print $4 }')"
		[ -z "$PORT" ] && abort "cound not get IPMI port"
		prompt "start $N (port [$PORT])"
		set -x
		#openstack baremetal node boot ${N}
		ipmitool -I lanplus -U admin -P password -H dl380 -p $PORT power on || abort "ipmi to port $PORT failed"
		#openstack baremetal node power on ${N}

		set +x
	done

	echo "waiting for ping"
	for N in $LIST; do
		echo -n "[$N]"
		while [ 1 ]; do
			pingtest $N && break
			echo -n "."
			sleep 1
		done
		echo ":up"
	done

	echo "waiting for ntp (retry every 10sec)"
	for N in $LIST; do
		while [ 1 ]; do
			H="`echo $N | sed -e 's|overcloud-cephstorage-|cephstorage|g'`"
			NTPREF="$(ssh heat-admin@$H /sbin/ntpq -pn | tail -1 | awk '{ print $1 }')"
			echo "$N: $NTPREF"
			[ "x$NTPREF" = 'x*10.10.1.1' ]  && break
			sleep 10
		done
	done
}


####
shutdown_list()
{
	LIST="$*"
	[ -z "$LIST" ] && return
	echo "suhtting down [$LIST].."
	for N in $LIST; do
		H="`echo $N | sed -e 's|overcloud-cephstorage-|cephstorage|g'`"
		pingtest $H || continue
		prompt "shutdown $N"
		ssh heat-admin@${H} '/usr/bin/sudo /usr/sbin/shutdown -h now'
	done

	echo "waiting for shutdoen.."
	for N in $LIST; do
		echo -n "[$N]"
		while [ 1 ]; do
			pingtest $N || break
			echo -n "."
			sleep 1
		done
		echo ":down"
	done
}


CHECK="`/usr/bin/whoami`.`/usr/bin/hostname -s`"
[ "x$CHECK" = "xstack.undercloud" ] || abort "CHECK=[$CHECK]"
CMD="`basename $0`"
echo "CMD=[$CMD]"


##################################### SHUTDOWN
if [ "$CMD" = "shutdown.sh" ] ; then
	CONTROL="$(cat $STATE | awk -F, '/,"control"$/ { print $2 }' | sed -e 's/"//g; s/\n/ /g' | sort -r | tr '\n' ' ')"
	COMPUTE="$(cat $STATE | awk -F, '/,"compute"$/ { print $2 }' | sed -e 's/"//g; s/\n/ /g' | sort -r | tr '\n' ' ')"
	STORAGE="$(cat $STATE | awk -F, '/,"ceph-storage"$/ { print $2 }' | sed -e 's/"//g; s/\n/ /g' | sort -r | tr '\n' ' ')"
	echo "CONTROL=[$CONTROL]"
	echo "COMPUTE=[$COMPUTE]"
	echo "STORAGE=[$STORAGE]"
	prompt "Really Shutdown OVERCLOUD ?"
	
	if [ -z "$1" ] || [ "$1" = "servers" ]; then
		. ~stack/overcloudrc || abort "~stack/overcloudrc err"
		prompt "delete running instances.."
		echo "geting list.."
		openstack server list --all-projects -f value -c ID -c Name | while read LINE; do
			ID="`echo $LINE | awk '{ print $1 }'`"
			NAME="`echo $LINE | awk '{ print $2 }'`"
			[ -z "$ID" ] && continue
			echo "delete instance[$NAME,$ID]..."
			set -x
			openstack server delete $ID
			set +x
		done
	fi
	
	if [ -z "$1" ] || [ "$1" = "compute" ]; then
		prompt "shutdown compute nodes [$COMPUTE]"
		shutdown_list "$COMPUTE"
		for N in $xCOMPUTE; do
			pingtest $N || continue
			ping -c 1 $N > /dev/null || continue
			prompt "shutdown $N"
			ssh heat-admin@${N} '/usr/bin/sudo /usr/sbin/shutdown -h now'
		done
	
		echo "waiting for compute nodes.."
		for N in $xCOMPUTE; do
			echo -n "[$N]"
			while [ 1 ]; do
				pingtest $N || break
				echo -n "."
				sleep 1
			done
		done
	fi
	
	if [ -z "$1" ] || [ "$1" = "ceph" ]; then
		shutdown_list "$STORAGE"
	fi
	
	if [ -z "$1" ] || [ "$1" = "control" ]; then
		echo "checking controll nodes.."
		for N in $CONTROL; do
			pingtest $N 
			if [ $? -eq 0 ]; then
				echo "controller[$N] is up.."
				ssh heat-admin@controller1 '/usr/bin/sudo /sbin/pcs cluster status' 
				if [ $? -eq 0 ]; then
					set -x
					ssh heat-admin@${N} '/usr/bin/sudo /sbin/pcs cluster stop --all'
					sleep 1
				else
					echo "cluster appears down..."
				fi
		
				break
			fi
			echo "controller[$N] is down.."
		done
		shutdown_list "$CONTROL"
	
	fi
	exit 0
fi
##################################### STARTUP
if [ "$CMD" = "startup.sh" ]; then
	CONTROL="$(cat $STATE | awk -F, '/,"control"$/ { print $2 }' | sed -e 's/"//g' | sort | tr '\n' ' ')"
	COMPUTE="$(cat $STATE | awk -F, '/,"compute"$/ { print $2 }' | sed -e 's/"//g' | sort | tr '\n' ' ')"
	STORAGE="$(cat $STATE | awk -F, '/,"ceph-storage"$/ { print $2 }' | sed -e 's/"//g' | sort | tr '\n' ' ')"
	echo "CONTROL=[$CONTROL]"
	echo "COMPUTE=[$COMPUTE]"
	echo "STORAGE=[$STORAGE]"
	
	if [ -z "$1" ] || [ "$1" = "control" ]; then
		prompt "start control nodes[$CONTROL]"
		startup_list "$CONTROL"
	fi


	if [ -z "x$1" ] || [ "$1" = "control-ntp" ]; then
		echo "checking NTP.."
		for N in $CONTROL; do
			ssh heat-admin@${N} 'hostname; sudo /sbin/ntpq -pn | tail -1'
		done
	fi

	if [ -z "$1" ] || [ "$1" = "control-ceph" ]; then
		echo "checking CEPH.."
		for N in $CONTROL; do
			ssh heat-admin@${N} 'sudo docker exec ceph-mon-$HOSTNAME ceph -s'
		done
	fi

	if [ -z "$1" ] || [ "$1" = "ceph" ]; then
		prompt "start ceph nodes[$STORAGE]"
		startup_list "$STORAGE"
	fi

	if [ -z "x$1" ] || [ "$1" = "ceph-ntp" ]; then
		echo "checking NTP.."
		for N in $STORAGE; do
			H="`echo $N | sed -e 's|overcloud-cephstorage-|cephstorage|g'`"
			ssh heat-admin@${H} 'hostname; sudo /sbin/ntpq -pn | tail -1'
		done
	fi

	if [ -z "$1" ] || [ "$1" = "compute" ]; then
		prompt "start compute nodes[$COMPUTE]"
		startup_list "$COMPUTE"
	fi




	exit 0
fi
##################################### STARTUP
