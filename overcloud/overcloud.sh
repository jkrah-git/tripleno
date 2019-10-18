#!/bin/bash
BASEDIR="`( cd $(dirname $0)/.. && pwd )`"
echo "BASEDIR=[$BASEDIR]"
. ${BASEDIR}/bin/prompt.inc || exit 1

CHECK="`/usr/bin/whoami`.`/usr/bin/hostname -s`"
[ "x$CHECK" = "xstack.undercloud" ] || abort "CHECK=[$CHECK]"

CONF=~/.overcloud.conf
## CONF should export the following
## EXT_BR= ovs-bridgle for External GW
## EXT_VLAN= VLAN id for External GW
## EXT_GW=  GW for external network (overclouds gw to the outside)
##  EXT_IF= External interface name
## EXT_NIC= nic (eth2)
## DOMS= [ controller compute ceph VMS to provision ]
## --------------
## eg.
# EXT_BR=br-ex
# EXT_VLAN=10
# EXT_GW=172.16.210.1
# EXT_NIC=eth2
#	DOMS="controller0 controller1 controller2 ceph0 ceph1 ceph2 compute0 compute1"
#	ANSWER_FILE=templates/answers/add_ceph.yaml
#	ANSWER_FILE=templates/answers/3-nodes.yaml
	set -x
 . $CONF || abort "CONF[$CONF] not found"
	set +x

[ -z "$EXT_BR" ] && abort "EXT_BR external ovs-bridege NOT set"
[ -z "$EXT_VLAN" ] && abort "EXT_VLAN external VLAN NOT set"
[ -z "$EXT_GW" ] && abort "EXT_GW not set"
[ -z "$EXT_NIC" ] && abort "EXT_NIC not set"
[ -z "$DOMS" ] && abort "DOMS not set"
[ -z "$ANSWER_FILE" ] && abort "ANSWER_FILE not set"

EXT_IF=vlan${EXT_VLAN}


JSON_DIR="`dirname $0`/../data/json"
[ -d "$JSON_DIR" ] || abort "JSON_DIR[$JSON_DIR] err"

prompt  "Install overcloud on to DOMS[$DOMS]"

##############################################################################################################################
##############################################################################################################################
###################################
#if [ ! -f /home/stack/.servers.txt ]; then
	########### (check) External vlan / external-gateway
	# ifconfig vlan10 2> /dev/null 
	ifconfig ${EXT_IF}  2> /dev/null 
	if [ $? -ne 0 ]; then
		set -x
		# sudo ovs-vsctl add-port $BR vlan10 -- set Interface vlan10 type=internal
		sudo ovs-vsctl add-port $EXT_BR ${EXT_IF} -- set Interface ${EXT_IF} type=internal
		sudo ifconfig ${EXT_IF}
		sudo ifconfig ${EXT_IF}  ${EXT_GW} netmask 255.255.255.0 up
		# sudo ovs-ofctl add-flow $BR "table=0,priority=5,in_port=eth2,dl_vlan=10,actions=strip_vlan,NORMAL"
		# sudo ovs-ofctl add-flow $BR "table=0,priority=5,in_port=vlan10,actions=mod_vlan_vid:10,NORMAL"
		sudo ovs-ofctl add-flow $EXT_BR "table=0,priority=5,in_port=$EXT_NIC,dl_vlan=$EXT_VLAN,actions=strip_vlan,NORMAL"
		sudo ovs-ofctl add-flow $EXT_BR "table=0,priority=5,in_port=$EXT_IF,actions=mod_vlan_vid:$EXT_VLAN,NORMAL"
		set +x
	fi
	ping -c 1 $EXT_GW > /dev/null || abort "ping GW($EXT_GW) failed"

	## now deal with overcloud nodes..
	. ~/stackrc  || abort "rc err"


	########### step 0. - test ipmi 
	prompt "(test ipmp).."
	rpm -q ipmitool || sudo yum -y install ipmitool.x86_64

	for DOM in $DOMS; do
		PORT="$(grep -i Port ${JSON_DIR}/${DOM}.json | awk -F\" '{ print $4 }')"
		echo -n "[$DOM] port[$PORT} ->"
		ipmitool -I lanplus -U admin -P password -H dl380 -p $PORT power status || abort "ipmi to poty $PORT failed"
	done

	########### step 1. - import nodes 
	if [ ! -f ~/.bare.nodes.txt ]; then
	prompt "continue (import [$DOMS]).."
		###################################
		for DOM in $DOMS; do
			echo "importing overcloud node[$DOM]"
			#openstack baremetal node delete $DOM
			set -x
			openstack overcloud node import ${JSON_DIR}/${DOM}.json
			set +x
		done
		openstack baremetal node list > ~/.bare.nodes.txt
	fi

	########### step 2. - inntrospect nodes 
	if [ ! -f ~/.inspected.nodes.txt ]; then
	prompt "continue (inntrospect [$DOMS]).."
		###################################
		echo ".. insoecting nodes: "
		set -x
		openstack overcloud node introspect --all-manageable --provide
		openstack overcloud profiles list > ~/.inspected.nodes.txt
		set +x
	fi

	########### step 3. - assign roles 
	if [ ! -f ~/.bare.roles.txt ]; then
	prompt "continue (assign roles [$DOMS]).."
		###################################
		for DOM in $DOMS; do
			echo $DOM | grep compute && ROLE="compute"
			echo $DOM | grep control && ROLE="control"
			echo $DOM | grep ceph && ROLE="ceph-storage"

			echo "importing overcloud node[$DOM] role[$ROLE]"
			if [ ! -z "$ROLE" ]; then
			set -x
				openstack baremetal node set --property capabilities="profile:$ROLE,boot_option:local" $DOM
				[ "$ROLE" = "ceph-storage" ] && openstack baremetal node set --property root_device='{"name": "/dev/vda"}' $DOM
			set +x
			else
				echo "ERR: Cant file role for [$DOM]"
			fi
		done
		openstack overcloud profiles list > ~/.bare.roles.txt
	fi
	
	### --------------- (start CEPH) -------------
	if [ "x$CEPH" = "xy" ]; then
		# check ansible is 2.6 and 'ceph-ansible.rpm' installed
		ANSVER="$(ansible --version | awk '/^ansible/ { print $2 }')"
		echo "ANSVER=[$ANSVER]"
		[ "x$ANSVER" = "x2.6.17" ] || abort "ansiblever needs to be 2.6.17"
		rpm -q ceph-ansible || abort "ceph-ansible not installed"


		## make the same as undercloud.sh
		DOCKER_DEST=10.10.1.5:5000
		echo "DOCKER_DEST=[$DOCKER_DEST]"
		if [ ! -f /home/stack/ceph_overcloud_images_environment.yaml ]; then
			prompt "image prepare .."
			set -x
	openstack overcloud container image prepare  --namespace=docker.io/tripleo$OSDIST \
	--push-destination=${DOCKER_DEST} \
	--tag-from-label {version}-{release} \
	--output-env-file=/home/stack/ceph_overcloud_images_environment.yaml \
	--output-images-file /home/stack/ceph_local_registry_images.yaml \
	-e /usr/share/openstack-tripleo-heat-templates/environments/ceph-ansible/ceph-ansible.yaml
			set +x
		fi
	
		
		if [ ! -f /home/stack/.ceph_overcloud_images_environment.downloaded ]; then
		 	prompt "image download .."
		 	set -x
		 	openstack overcloud container image upload  --config-file  /home/stack/ceph_local_registry_images.yaml --verbose
		 	set +x
		fi
	fi
	### --------------- (end CEPH) -------------


	###########  symlink templates/
	if [ ! -f ~/templates/network_data.yaml ]; then
		###################################
		# ln -s /data/nfs/openstack/tripleo/templates . || abort "templates symlink err"
		echo ".. symlinking in ~/templates"
		( cd `dirname $0`/.. && P="`pwd`"
		  cd ~/ ; ln -s $P/templates . )
		[  -f ~/templates/network_data.yaml ] || abort "~/templates/network_data.yaml not found.."
		ls -ld ~/templates
	fi

if [ ! -f ~/.overcloud.end ]; then	
	########### step 2. - (re)create rendered templates
	prompt "continue (render templates [$DOMS]).."
	[ -d ~/rendered ] && rm -rf ~/rendered
	/usr/share/openstack-tripleo-heat-templates/tools/process-templates.py \
	-p /usr/share/openstack-tripleo-heat-templates/ \
	-o ~/rendered  -n ~/templates/network_data.yaml
	###################################
	
	########### step 3. - inject interface files
	# /bin/cp templates/ctl-eth0_brex-eth1/* rendered/network/config/single-nic-vlans/ || exit
	# /bin/cp ~/templates/inject-trust-anchor.yaml ~/rendered/environments/ssl/inject-trust-anchor.yaml  || abort "cp err"
	/bin/cp ~/templates/nics/current/* ~/rendered/network/config/single-nic-vlans/ || abort "cp err"
	`dirname $0`/../bin/insert-cert.sh > ~/rendered/environments/ssl/inject-trust-anchor.yaml  || abort "cert err"

	##################################

	########### step 4. - run main install
	prompt "continue (main overcloud depploy ).."
	echo 
	echo "Finished aprox (`date +%r -d 'now + 5100 seconds'`)"
	for I in `seq 10 -1 1`; do echo -n "$I.. "; sleep 1; done; echo 

	cd ~ || abort "cd err"
	. ~/stackrc || abort
	set -x
	date > ~/.overcloud.start 
	openstack overcloud deploy -n ~/templates/network_data.yaml --answers-file $ANSWER_FILE >  ~/overcloud_deploy.log 2>&1 
	[ "$?" = "0" ] || abort
	date > ~/.overcloud.end
	
	if [ ! -f  ~/overcloudrc ]; then
		mv ~/.overcloud.end ~/.overcloud.err
		abort "err: overcloudrc not fouund"
	fi
	###################################
	# /data/nfs/openstack/templates/status.sh
	`dirname $0`/../bin/status.sh	
	. overcloudrc || abort
	openstack network create --share --external --provider-network-type flat --provider-physical-network datacentre external
	openstack subnet create --network external --gateway 172.16.100.1  --dhcp --subnet-range 172.16.100.0/24 --allocation-pool start=172.16.100.200,end=172.16.100.250 external-subnet
fi

`dirname $0`/../bin/status.sh	
cat << EOinstallmsg
#######################
## run on all controllers iptables memcached (tcp/11211) ..
iptables -I INPUT 5  -i vlan13 -p tcp --dport 11211 -j ACCEPT  -m state --state NEW -m comment --comment "added memcached"
## perm fix
grep '"added memcached"' /etc/sysconfig/iptables || \\
sed -i '9i-A INPUT -i vlan13 -p tcp --dport 11211  -m state --state NEW -m comment --comment "added memcached" -j ACCEPT' /etc/sysconfig/iptables
#######################
EOinstallmsg

exit 0



if [ ! -f /home/stack/operator.test.rc ]; then
	## END (CONTROLLER)
	#########################################################################################################
	################## default (br-ex:datacentre) provider network (currenlty br-ex=prov.i/f)
	. overcloudrc || abort
	set -x
	openstack floating ip create external
	## 172.16.101.208
	
	################## create project /users/roles
	openstack project create test
	openstack user create --project test --password architect architect
	openstack role add  --project test --user architect  admin
	
	openstack user create --project test --password operator operator
	openstack role add  --project test --user operator _member_
	# /data/nfs/openstack/bin/keystone_rc.sh operator operator test > operator.test.rc
	# /data/nfs/openstack/bin/keystone_rc.sh architect architect test > architect.test.rc
	/data/nfs/openstack/tripleo/bin/keystone_rc.sh operator operator test > operator.test.rc
	/data/nfs/openstack/tripleo/bin/keystone_rc.sh architect architect test > architect.test.rc
	################## test users
	. operator.test.rc || abort
	openstack network list
	. architect.test.rc  || abort
	openstack network list
	##################
	
	. architect.test.rc
	openstack image create --file /data/nfs/openstack/images/CentOS-7-x86_64-GenericCloud.qcow2 --disk-format qcow2 centos7
	openstack image create --file /data/nfs/openstack/images/cirros-0.3.5-x86_64-disk.img --disk-format qcow2 cirros
	openstack flavor create --ram 8100 --disk 10 default
	openstack floating ip create external
	## 172.16.4.203
	################################################################
	. operator.test.rc 
	openstack security group create open_ssh
	openstack security group rule create open_ssh --dst-port 22
	openstack security group rule create open_ssh --protocol icmp
	openstack keypair create --private-key .ssh/cloud-user.priv cloud-user
	chmod 600 .ssh/cloud-user.priv 
	################################################################
	. operator.test.rc 
	openstack network create internal
	openstack subnet create --network internal --subnet-range 10.0.0.0/24 --dhcp --allocation-pool start=10.0.0.32,end=10.0.0.64 --dns-nameserver 172.16.10.3 internal-subnet
	openstack router create external-router
	openstack router set --external-gateway external external-router
	openstack router add subnet external-router internal-subnet
	##########
fi

if [ ! -f "/home/stack/.neutron.ok" ]; then
cat << EOF > /home/stack/.neutron.ok
######### (START RUN ON CONTROLLER)
##  enable_isolated_metadata=true ## shoould be ok ## CHECK: 
grep ^enable_isolated_metadata=  /var/lib/config-data/puppet-generated/neutron/etc/neutron/dhcp_agent.ini

docker exec -it nova_scheduler  nova-manage cell_v2 discover_hosts --verbose
######### (END RUN ON CONTROLLER)
EOF
cat /home/stack/.neutron.ok
exit 
fi

if [ ! -f "/home/stack/.server.ok" ]; then
. ~/operator.test.rc || abort "~/operator.test.rc failed"
set -x
openstack server create --flavor default --key-name cloud-user --security-group open_ssh --wait --image centos7 --network external ext-server
openstack server create --flavor default --key-name cloud-user --security-group open_ssh --wait --image centos7 --network internal int-server
openstack floating ip list
openstack server list
echo \# openstack server add floating ip int-server X.X.X.X
touch /home/stack/.server.ok
fi



exit
openstack server delete int-server
openstack server delete ext-server
