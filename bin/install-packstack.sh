#!/bin/bash
. `dirname $0`/prompt.inc || exit 1

SIGFILE=/var/tmp/.packstack.ok
[ -f $SIGFILE ] || abort "first: touch $SIGFILE"

LOCALNAME="`hostname -s`"

ANSWER_FILE=~/packstack_answerfile.txt
LOG_FILE=~/packstack_install.stdout
## [ "`/usr/bin/whoami`" = "root" ] || abort "must be ran as root"
if [ "`/usr/bin/whoami`" = "root" ]; then
	prompt "Install packstack on[$LOCALNAME]"
	set -x
	if [ ! -f /var/tmp/packstack.dis_nmi ]; then
		systemctl disable firewalld
		systemctl stop firewalld
		systemctl disable NetworkManager
		systemctl stop NetworkManager
		systemctl enable network
		systemctl start network
		touch /var/tmp/packstack.dis_nmi
	fi

	rpm -q openstack-packstack 
	if [ $? -ne 0 ]; then
		yum install -y yum-utils  https://rdoproject.org/repos/rdo-release.rpm
		yum-config-manager --enable openstack-queens
		yum update -y
		yum install -y openstack-packstack
		rpm -q openstack-packstack  || abort "openstack-packstack.rpm did not install"
	fi

	if [ ! -f $ANSWER_FILE ]; then
		packstack --allinone \
--provision-demo=n \
--os-neutron-ovs-bridge-mappings=extnet:br-ex \
--os-neutron-ovs-bridge-interfaces=br-ex:eth0 \
--os-neutron-ml2-type-drivers=vxlan,flat \
--ntp-servers=172.16.10.3 \
--os-heat-install=y \
--gen-answer-file=$ANSWER_FILE
	fi
	set +x
	[ -f "$ANSWER_FILE" ] || abort "err with [$ANSWER_FILE]"
	
	packstack --validate-answer-file=$ANSWER_FILE || abort "validation failed"
	print "ANSWER_FILE[$ANSWER_FILE] passwd validation.."
	print "=================================="
	print "Ready for main packstack install.."
	print "Finished aprox (`date +%r -d 'now + 2040 seconds'`)"
	print "=================================="
	prompt "run packstack installer"
	print "Logging to [$LOG_FILE]"


# Oct 20 20:18 packstack_answerfile.txt
# date (end of install) Sun Oct 20 20:54:36 AEDT 2019
# aprox 34min (2040sec)
	print "Finished aprox (`date +%r -d 'now + 2040 seconds'`)"
	let START_TIME=`date +%s`
	packstack --answer-file=$ANSWER_FILE > $LOG_FILE
# || abort "packstack install err"
	let END_TIME=`date +%s`
	let TOTAL_TIME=$END_TIME-$START_TIME
	let TOTAL_MIN=$TOTAL_TIME/60
	print "FINISHED: Time[$TOTAL_TIME]sec  (aprox $TOTAL_MIN min)"

	[ -f ~/keystonerc_admin ] || abort "~/keystonerc_admin not created.."

	. ~/keystonerc_admin || abort "~/keystonerc_admin err"
	openstack network create --share --external --provider-network-type flat --provider-physical-network extnet external
        openstack subnet create --network external --gateway 172.16.100.1  --dhcp --subnet-range 172.16.100.0/24 --allocation-pool start=172.16.100.200,end=172.16.100.250 external-subnet

fi
