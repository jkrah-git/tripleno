#!/bin/bash
BASEDIR="`( cd $(dirname $0)/.. && pwd )`"
echo "BASEDIR=[$BASEDIR]"

# . `dirname $0`/../bin/prompt.inc || exit 1
. ${BASEDIR}/bin/prompt.inc || exit 1


CHECK="`/usr/bin/whoami`.`/usr/bin/hostname -s`"
[ "x$CHECK" = "xstack.undercloud" ] || abort "CHECK=[$CHECK]"

if [ ! -f /home/stack/operator.test.rc ]; then
	## END (CONTROLLER)
	#########################################################################################################
	################## default (br-ex:datacentre) provider network (currenlty br-ex=prov.i/f)
	. ~/overcloudrc || abort
	set -x
	openstack floating ip create external
	
	################## create project /users/roles
	openstack project create test
	openstack user create --project test --password architect architect
	openstack role add  --project test --user architect  admin
	
	openstack user create --project test --password operator operator
	openstack role add  --project test --user operator _member_
	${BASEDIR}/bin/keystone_rc.sh operator operator test > ~/operator.test.rc
	${BASEDIR}/bin/keystone_rc.sh architect architect test > ~/architect.test.rc
	################## test users
	. ~/operator.test.rc || abort
	openstack network list
	. ~/architect.test.rc  || abort
	openstack network list
	##################
	
	. ~/architect.test.rc || abort
	openstack image create --file /data/nfs/openstack/images/CentOS-7-x86_64-GenericCloud.qcow2 --disk-format qcow2 centos7
	openstack image create --file /data/nfs/openstack/images/cirros-0.3.5-x86_64-disk.img --disk-format qcow2 cirros
	openstack flavor create --ram 8100 --disk 10 default
	openstack floating ip create external
	## 172.16.4.203
	################################################################
	. ~/operator.test.rc || abort
	openstack security group create open_ssh
	openstack security group rule create open_ssh --dst-port 22
	openstack security group rule create open_ssh --protocol icmp
	openstack keypair create --private-key ~/.ssh/cloud-user.priv cloud-user
	chmod 600 .ssh/cloud-user.priv 
	################################################################
	openstack network create internal
	openstack subnet create --network internal --subnet-range 10.0.0.0/24 --dhcp --allocation-pool start=10.0.0.32,end=10.0.0.64 --dns-nameserver 172.16.10.3 internal-subnet
	openstack router create external-router
	openstack router set --external-gateway external external-router
	openstack router add subnet external-router internal-subnet
	##########
fi


if [ ! -f "/home/stack/.server.ok" ]; then
	. ~/operator.test.rc || abort 
	set -x
	openstack server create --flavor default --key-name cloud-user --security-group open_ssh --wait --image centos7 --network external ext-server
	openstack server create --flavor default --key-name cloud-user --security-group open_ssh --wait --image centos7 --network internal int-server
	openstack floating ip list
	openstack server list
	echo \# openstack server add floating ip int-server X.X.X.X
	touch /home/stack/.server.ok
	exit
fi

	set -x
openstack server delete int-server
openstack server delete ext-server
