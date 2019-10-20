#!/bin/bash
BASEDIR="`( cd $(dirname $0)/.. && pwd )`"
. ${BASEDIR}/bin/prompt.inc || exit 1
CHECK="`/usr/bin/whoami`.`/usr/bin/hostname -s`"
[ "x$CHECK" = "xstack.undercloud" ] || abort "CHECK=[$CHECK]"
CONF=~/.overcloud.conf
print "BASEDIR=[$BASEDIR] CONF=[$CONF]"
. $CONF || abort "CONF[$CONF] not found"

CMD="`basename $0`"
print "CMD=[$CMD]"

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
	print "start [$LIST].."
	for N in $LIST; do
		#pingtest $N && continue
		DOM="`echo $N | sed -e 's|overcloud-cephstorage-|ceph|g'`"
		PORT="$(grep -i Port ${JSON_DIR}/${DOM}.json | awk -F\" '{ print $4 }')"
		[ -z "$PORT" ] && abort "cound not get IPMI port"
		STATE="$(ipmitool -I lanplus -U admin -P password -H dl380 -p $PORT power status)" || abort "ipmi err"
		print "$N ($PORT) is [$STATE]"
		[ "x$STATE" = "xChassis Power is on" ] && continue
		#prompt "start $N (port [$PORT])"
		set -x
		ipmitool -I lanplus -U admin -P password -H dl380 -p $PORT power on || abort "ipmi to port $PORT failed"
		#openstack baremetal node power on ${N}
		set +x
		wait 15
	done

	print "waiting for ping"
	for N in $LIST; do
		echo -n "[$N]"
		while [ 1 ]; do
			pingtest $N && break
			echo -n "."
			sleep 1
		done
		echo ":up"
	done

	print "waiting for ntp (retry every 10sec) client restart every 10 fails"
	for N in $LIST; do
		let C=0
		while [ 1 ]; do
			H="`echo $N | sed -e 's|overcloud-cephstorage-|cephstorage|g'`"
			NTPREF="$(ssh heat-admin@$H /sbin/ntpq -pn | tail -1 | awk '{ print $1 }' 2>&1)"
			echo "$N: $NTPREF"
			[ "x$NTPREF" = 'x*10.10.1.1' ]  && break
			let C=$C+1
			if [ $C -gt 9 ]; then
				print "restarting rmeote (ntp) client.."
				set -x
				ssh heat-admin@${H} 'sudo systemctl stop ntpd'
				ssh heat-admin@${H} 'sudo ntpdate -d -q 10.10.1.1'
				ssh heat-admin@${H} 'sudo systemctl start ntpd'
				set +x
				let C=0
			fi
			sleep 10
		done
	done
}


####
shutdown_list()
{
	LIST="$*"
	[ -z "$LIST" ] && return
	print "shut down [$LIST].."
	for N in $LIST; do
		H="`echo $N | sed -e 's|overcloud-cephstorage-|cephstorage|g'`"
		pingtest $H || continue
		ssh heat-admin@${H} '/usr/bin/sudo /usr/sbin/shutdown -h now'
	done

	print "waiting for shutdown.."
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



##################################### SHUTDOWN
full_shutdown()
{
#if [ "$CMD" = "shutdown.sh" ] ; then
	CONTROL="$(cat $STATE | awk -F, '/,"control"$/ { print $2 }' | sed -e 's/"//g; s/\n/ /g' | sort -r | tr '\n' ' ')"
	COMPUTE="$(cat $STATE | awk -F, '/,"compute"$/ { print $2 }' | sed -e 's/"//g; s/\n/ /g' | sort -r | tr '\n' ' ')"
	STORAGE="$(cat $STATE | awk -F, '/,"ceph-storage"$/ { print $2 }' | sed -e 's/"//g; s/\n/ /g' | sort -r | tr '\n' ' ')"
	print "CONTROL=[$CONTROL]"
	print "COMPUTE=[$COMPUTE]"
	print "STORAGE=[$STORAGE]"
	prompt "STOP Overcloud ?"
	
	if [ -z "$1" ] || [ "$1" = "servers" ]; then
		. ~stack/overcloudrc || abort "~stack/overcloudrc err"
		prompt "delete ALL running 'instances'.."
		print "checking for running 'instances'.."
		openstack server list --all-projects -f value -c ID -c Name -c Status | while read LINE; do
			ID="`echo $LINE | awk '{ print $1 }'`"
			NAME="`echo $LINE | awk '{ print $2 }'`"
			STATE="`echo $LINE | awk '{ print $3 }'`"
			echo "$NAME [$ID] is STATE[$STATE]"
			[ "x$STATE" = "xACTIVE" ] || continue
			[ -z "$ID" ] && continue
			print "delete instance[$NAME,$ID]..."
			set -x
			openstack server delete $ID
			set +x
		done
	fi

	if [ -z "$1" ] || [ "$1" = "compute" ]; then
		prompt "shutdown compute nodes [$COMPUTE]"
		shutdown_list "$COMPUTE"
	fi
	
	if [ -z "$1" ] || [ "$1" = "ceph" ]; then
		prompt "shutdown ceph nodes [$STORAGE]"
		shutdown_list "$STORAGE"
	fi
	
	if [ -z "$1" ] || [ "$1" = "control" ]; then
		print "checking controll nodes.."
		for N in $CONTROL; do
			pingtest $N 
			if [ $? -eq 0 ]; then
				print "controller[$N] is up.."
				ssh heat-admin@${N} '/usr/bin/sudo /sbin/pcs cluster status' 
				if [ $? -eq 0 ]; then
					set -x
					ssh heat-admin@${N} '/usr/bin/sudo /sbin/pcs cluster stop --all'
					set +x
					sleep 1
				else
					print "cluster appears down..."
				fi
		
				break
			fi
			print "controller[$N] is down.."
		done
		shutdown_list "$CONTROL"
	
	fi
	#exit 0
#fi
}
##################################### STARTUP
full_startup()
{
#if [ "$CMD" = "startup.sh" ]; then
	CONTROL="$(cat $STATE | awk -F, '/,"control"$/ { print $2 }' | sed -e 's/"//g' | sort | tr '\n' ' ')"
	COMPUTE="$(cat $STATE | awk -F, '/,"compute"$/ { print $2 }' | sed -e 's/"//g' | sort | tr '\n' ' ')"
	STORAGE="$(cat $STATE | awk -F, '/,"ceph-storage"$/ { print $2 }' | sed -e 's/"//g' | sort | tr '\n' ' ')"
	print "CONTROL=[$CONTROL]"
	print "COMPUTE=[$COMPUTE]"
	print "STORAGE=[$STORAGE]"
	prompt "START Overcloud ?"

	print "checking local NTP..(every 30s) (can reuire 20mins uptime)"
	while [ 1 ]; do
		echo -n "Uptime[`uptime`] : local NTP LEAP="
		LOCAL_LEAP="$(ntpdate -d 10.10.1.1 2>&1 | grep ^stratum | sed -e 's|.*leap \([0-9]*\).*|\1|g')"
		echo "[$LOCAL_LEAP]"
		[ "x$LOCAL_LEAP" = "x00" ] && break
		sleep 30
	done

	if [ -z "$1" ] || [ "$1" = "control" ]; then
		prompt "start control nodes[$CONTROL]"
		startup_list "$CONTROL"
	fi

	if [ -z "$1" ] || [ "$1" = "ceph" ]; then
		prompt "start ceph nodes[$STORAGE]"
		startup_list "$STORAGE"
	fi

	if [ -z "$1" ] || [ "$1" = "compute" ]; then
		prompt "start compute nodes[$COMPUTE]"
		startup_list "$COMPUTE"
	fi

    if [ ! -z "$STORAGE" ]; then
	print "waiting for ceph to come good"
	for N in $CONTROL; do
		pingtest $N 
		if [ $? -eq 0 ]; then
			print "controller[$N] is up.."
			while [ 1 ]; do
				CEPH_HEALTH=$(ssh heat-admin@${N} 'sudo docker exec ceph-mon-$HOSTNAME ceph health')
				echo "[$N]: CEPH_HEALTH=[$CEPH_HEALTH]"
				[ "$CEPH_HEALTH" = "HEALTH_OK" ] && break
				wait 15
			done
			break
		fi
	done
    fi

	print "pcs cleanup.. in 10sec"
	wait 10
	for N in $CONTROL; do
		set -x
		ssh heat-admin@${N} 'sudo pcs resource cleanup'
		set +x
	done


	#exit 0
#fi
}
##################################### STARTUP

let START_TIME=`date +%s`

[ "$CMD" = "startup.sh" ] && full_startup
[ "$CMD" = "shutdown.sh" ] && full_shutdown

let END_TIME=`date +%s`

let TOTAL_TIME=$END_TIME-$START_TIME
let TOTAL_MIN=$TOTAL_TIME/60
print "finished [$CMD] in $TOTAL_TIME (sec) (aprox $TOTAL_MIN min)"

