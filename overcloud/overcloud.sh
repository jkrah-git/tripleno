#!/bin/bash
BASEDIR="`( cd $(dirname $0)/.. && pwd )`"
echo "BASEDIR=[$BASEDIR]"
. ${BASEDIR}/bin/prompt.inc || exit 1
CHECK="`/usr/bin/whoami`.`/usr/bin/hostname -s`"
[ "x$CHECK" = "xstack.undercloud" ] || abort "CHECK=[$CHECK]"
CONF=~/.overcloud.conf
 . $CONF || abort "CONF[$CONF] not found"




JSON_DIR="${BASEDIR}/data/json"
[ -d "$JSON_DIR" ] || abort "JSON_DIR[$JSON_DIR] err"

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
	set +x

[ -z "$EXT_BR" ] && abort "EXT_BR external ovs-bridege NOT set"
[ -z "$EXT_VLAN" ] && abort "EXT_VLAN external VLAN NOT set"
[ -z "$EXT_GW" ] && abort "EXT_GW not set"
[ -z "$EXT_NIC" ] && abort "EXT_NIC not set"
[ -z "$DOMS" ] && abort "DOMS not set"
[ -z "$ANSWER_FILE" ] && abort "ANSWER_FILE not set"
## make the same as undercloud.sh
# DOCKER_DEST=10.10.1.5:5000
# OSDIST=queens
[ -z "$DOCKER_DEST" ] && abort "DOCKER_DEST not set in config"
[ -z "$OSDIST" ] && abort "OSDIST not set in config"

EXT_IF=vlan${EXT_VLAN}


print "ANSWER_FILE=[$ANSWER_FILE]"
if [ -f $ANSWER_FILE ] ; then
	echo "############################"
	cat $ANSWER_FILE
	echo "############################"
fi

TDIR=$BASEDIR/templates
[ -d ~/templates ] && TDIR=~/templates

if [ -f $TDIR/node-info.yaml ]; then
	grep Count $TDIR/node-info.yaml
else 
	print "WARN: Cant preview nodef-info.yaml"
fi
print "ARE NODE COUNTS CORRECT"

prompt  "Install overcloud on to DOMS[$DOMS]"


let START_TIME=`date +%s`
##############################################################################################################################
##############################################################################################################################
###################################
#if [ ! -f /home/stack/.servers.txt ]; then
	########### (check) External vlan / external-gateway
	# ifconfig vlan10 2> /dev/null 
	if [ ! -f /etc/sysconfig/network-scripts/ifcfg-${EXT_IF} ]; then
		print "WARN: ifcfg-${EXT_IF} does not exist"
		if [ -f ${BASEDIR}/undercloud/ifcfg-${EXT_IF} ]; then 
			print "copiying ${BASEDIR}/undercloud/ifcfg-${EXT_IF}  to /etc/sysconfig/network-scripts/"
			sudo cp -p ${BASEDIR}/undercloud/ifcfg-${EXT_IF} /etc/sysconfig/network-scripts/ || abort "cp err"
		fi
	fi

	ifconfig ${EXT_IF}  2> /dev/null 
	if [ $? -ne 0 ]; then
		print "manually bringin up $EXT_IF"
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
			print "importing overcloud node[$DOM]"
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
		print ".. insoecting nodes: "
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

			print "importing overcloud node[$DOM] role[$ROLE]"
			if [ ! -z "$ROLE" ]; then
			set -x
				openstack baremetal node set --property capabilities="profile:$ROLE,boot_option:local" $DOM
				[ "$ROLE" = "ceph-storage" ] && openstack baremetal node set --property root_device='{"name": "/dev/vda"}' $DOM
			set +x
			else
				abort "ERR: Cant file role for [$DOM]"
			fi
		done
		openstack overcloud profiles list > ~/.bare.roles.txt
	fi
	
	print "DOCKER_DEST=[$DOCKER_DEST] OSDIST[$OSDIST]"
	### --------------- (start CEPH) -------------
	if [ "x$CEPH" = "xy" ]; then
		if [ ! -f /home/stack/ceph_overcloud_images_environment.yaml ]; then

			# check ansible is 2.6 and 'ceph-ansible.rpm' installed
			ANSVER="$(ansible --version | awk '/^ansible/ { print $2 }')"
			print "ANSVER=[$ANSVER]"
			[ "x$ANSVER" = "x2.6.17" ] || abort "ansiblever needs to be 2.6.17"
			rpm -q ceph-ansible || abort "ceph-ansible not installed"
			prompt "(ceph) image prepare .."
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
			touch /home/stack/.ceph_overcloud_images_environment.downloaded
		fi
	fi
	### --------------- (end CEPH) -------------

	if [ -z "$DOWNLOAD_OVN" ]; then
		print "DOWNLOAD_OVN is NOT set.."
	else
		print "DOWNLOAD_OVN is SET.."
		SRC_FILE=/usr/share/openstack-tripleo-heat-templates/environments/neutron-ml2-ovn-ha.yaml
		REG_FILE=ovn_local_registry_images.yaml
		ENV_FILE=ovn_overcloud_images_environment.yaml

		if [ ! -f /home/stack/$REG_FILE ]; then
			prompt "(ovn) image prepare .."
			set -x
			openstack overcloud container image prepare  --namespace=docker.io/tripleo$OSDIST \
				--push-destination=${DOCKER_DEST} \
				--tag-from-label {version}-{release} \
				--output-env-file=/home/stack/${ENV_FILE} \
				--output-images-file /home/stack/${REG_FILE} \
				-e ${SRC_FILE}
			set +x
		fi

		if [ ! -f /home/stack/.ovn_overcloud_images_environment.downloaded ]; then
		 	prompt "(ovn) image download .."
		 	set -x
		 	openstack overcloud container image upload  --config-file  /home/stack/${REG_FILE} --verbose
		 	set +x
			touch /home/stack/.ovn_overcloud_images_environment.downloaded
		fi
	fi


	###########  symlink templates/
	if [ ! -f ~/templates/network_data.yaml ]; then
		###################################
		# ln -s /data/nfs/openstack/tripleo/templates . || abort "templates symlink err"
		print ".. symlinking in ~/templates"
		( cd `dirname $0`/.. && P="`pwd`"
		  cd ~/ ; ln -s $P/templates . )
		[  -f ~/templates/network_data.yaml ] || abort "~/templates/network_data.yaml not found.."
		ls -ld ~/templates
	fi

if [ ! -f ~/.overcloud.end ]; then
	# Notes on rendering
	# looks to assume: External IP  on provision netowrk - override with template
	########### step 2. - (re)create rendered templates
	prompt "continue (render templates [$DOMS]).."
	[ -d ~/rendered ] && rm -rf ~/rendered
	[ -d ~/rendered.orig ] && rm -rf ~/rendered.orig
	/usr/share/openstack-tripleo-heat-templates/tools/process-templates.py \
	-p /usr/share/openstack-tripleo-heat-templates/ \
	-o ~/rendered  -n ~/templates/network_data.yaml
	cp -pr ~/rendered ~/rendered.orig 
	###################################
	
	########### step 3. - inject interface files
	/bin/cp ~/templates/nics/current/* ~/rendered/network/config/single-nic-vlans/ || abort "cp err"

	if [ ! -z "$DOWNLOAD_OVN" ]; then
#		# brute force external_from_pool.yaml
#		print "brute forcing 'external_from_pool'.."
#		SED='s|\(.*OS::TripleO::Compute::Ports::ExternalPort:.*\)/noop.yaml|\1\/external_from_pool.yaml|g'
#		############
#		for F in `grep -rl 'OS::TripleO::Compute::Ports::ExternalPort:' ~/rendered/`; do 
#			ls -l $F || break
#			sed -i.pre-ovn "$SED" $F
#		done

		# add external to compute nic-config
		cp -p ~/templates/nics/current/compute-ovn.yaml ~/rendered/network/config/single-nic-vlans/compute.yaml || abort 'overwrite comp nics for OVN failed'
		# add export 'port' defn
		cp -p ~/templates/environments/ips-from-pool-all.yaml ~/rendered/environments/ips-from-pool-all.yaml

		grep OS::TripleO::Compute::Ports::ExternalPort ~/rendered/environments/network-isolation.yaml || cat >> ~/rendered/environments/network-isolation.yaml << EOFextport 

# Externa/Compute Port assignment for OVN
# OS::TripleO::Compute::Ports::ExternalPort: ../network/ports/external_from_pool.yaml
  OS::TripleO::Compute::Ports::ExternalPort: ../network/ports/external.yaml

EOFextport
	fi

	`dirname $0`/../bin/insert-cert.sh > ~/rendered/environments/ssl/inject-trust-anchor.yaml  || abort "cert err"


	print "####################### DIFFS ##################"
	set -x
	diff -r ~/rendered.orig ~/rendered
	set +x
	prompt " ############ DIFF OK ?? ##############"


	##################################
	let END_TIME=`date +%s`
	let PREP_TIME=$END_TIME-$START_TIME
	let PREP_MIN=$PREP_TIME/60
	print "pre-deployedment PREP took ($PREP_TIME)s (aprox $PREP_MIN min)"

	########### step 4. - run main install
	
	prompt "continue (main overcloud depploy ).."
	print 
	print "Finished aprox (`date +%r -d 'now + 5100 seconds'`)"
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

