#!/bin/bash
. `dirname $0`/../bin/prompt.inc || exit 1

OSDIST=queens
#OSDIST=rocky

if [ -f  ~stack/undercloud.conf ]; then
	echo "using existing ~stack/undercloud.conf"
	UNDERCLOUD_CONF=~stack/undercloud.conf
else
	UNDERCLOUD_CONF=`dirname $0`/undercloud.conf.10.10.1.x
fi





echo "OSDIST=[$OSDIST] UNDERCLOUD_CONF=[$UNDERCLOUD_CONF]"

UCHOST="$(grep ^undercloud_hostname $UNDERCLOUD_CONF |  awk -F= '{ print $2 }'  |  sed -e 's| ||g')"
LOCAL_IP="$(grep ^local_ip $UNDERCLOUD_CONF |  awk -F= '{ print $2 }'  |  sed -e 's| ||g')"
#TO_REPOS="https://trunk.rdoproject.org/centos7/current/python2-tripleo-repos-0.0.1-0.20190724014728.1cf6e0b.el7.noarch.rpm"
#TO_REPOS="https://trunk.rdoproject.org/centos7/current/python2-tripleo-repos-0.0.1-0.20191001113300.9dba973.el7.noarch.rpm"
TO_REPOS="https://trunk.rdoproject.org/centos7/current/python2-tripleo-repos-0.0.1-0.20191012080333.fbcaf55.el7.noarch.rpm"
echo "UCHOST=[$UCHOST] LOCAL_IP[$LOCAL_IP]"
if [ ! "`hostname`" = "$UCHOST" ]; then
	echo "hostname[`hostname`] != UCHOST[$UCHOST["
	exit 2
fi

LOCALNAME="`hostname -s`"
if [ "`/usr/bin/whoami`" = "root" ]; then
	set -x
	if [ -z "`grep stack /etc/passwd`" ]; then

		prompt "update eth1 and add stack user"
		CURIP="$(ifconfig  eth1 | grep netmask | awk '{ print $2 }')"
		NEWIP="$(echo $LOCAL_IP |  sed -e 's|/24$||g')"
		echo "CURIP=[$CURIP] , NEWIP=[$NEWIP]"
		if [ ! "$CURIP" = "$NEWIP" ]; then
			nmcli connection modify eth1 ipv4.method manual ipv4.addresses "${LOCAL_IP}"  autoconnect yes \
				ipv4.dns 172.16.10.3,172.16.10.193 ipv4.dns-search shopsmart.au.nu
			systemctl disable NetworkManager; systemctl stop NetworkManager ; systemctl start network ; systemctl enable network
		fi
		
		## -------------------------------
		grep $LOCALNAME /etc/hosts || echo "$LOCALIP ${LOCALNAME}.shopsmart.au.nu" >> /etc/hosts
		
		useradd stack  || exit 2
		echo "stack" | passwd --stdin stack
		echo "stack ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/stack
		chmod 0440 /etc/sudoers.d/stack
	fi
	
	rpm -q python2-tripleo-repos || yum -y localinstall "$TO_REPOS"
	rpm -q python2-tripleo-repos || exit
	set +x
	yum erase libvirt-daemon-driver-network
	systemctl disable libvirtd 
	yum -y update
	echo "## Reboot and login as 'stack' and rerun \"$0\""
	#su - stack -c "$0"
	exit
fi

if [ ! "`/usr/bin/whoami`" = "stack" ]; then
	echo "Must be run as root or stack.."
	exit 1
fi
## ------------------------- MAIN INSTALL
	echo "(stack) undercloud installer..."
	[ -f /home/stack/.ssh/id_rsa ] || ssh-keygen -N "" -f /home/stack/.ssh/id_rsa

	if [ -z "$1" ]  || [ "$1" = "undercloud" ]; then

		## REPO PACKAGES
		rpm -q python-tripleoclient 2> /dev/null 
		if [ $? -eq 0 ]; then
			echo "## python-tripleoclient installed.. "
		else
			echo "########################"
			echo "# Installing python-tripleoclient"
			echo "########################"
			#sudo yum -y localinstall https://trunk.rdoproject.org/centos7/current/python2-tripleo-repos-0.0.1-0.20190724014728.1cf6e0b.el7.noarch.rpm || exit
			sudo -E tripleo-repos -b $OSDIST current ceph  || exit
			sudo yum -y install yum-plugin-priorities epel-release  python-tripleoclient || exit
			sudo yum -y update
			echo "## python-tripleoclient installed.. "
		fi
		
		## CONFIG
		if [ -f  ~/undercloud.conf ]; then
			echo "using existing ~/undercloud.conf"
		else
			cp -p $UNDERCLOUD_CONF ~/undercloud.conf  || exit 1
			echo "Copied in [$UNDERCLOUD_CONF]"
		fi

		echo "############ using undercloud settings ##################"
		egrep -v '^#|^$'  ~/undercloud.conf
		echo "#########################"

		if [ -f ~/.undercloud.start ]; then
			echo "~/.undercloud.start already exists.. skipping pre-install"
		else
			echo "hit enter to install the undercloud.."
			read CH
			set -x
			pgrep dnsmasq && sudo pkill dnsmasq
			pgrep dnsmasq && exit 1
			date > ~/.undercloud.start
			[  -f ~/.undercloud.end ] && rm ~/.undercloud.end
			openstack undercloud install || exit 1
			date > ~/.undercloud.end
			set +x
		fi

		if [ ! -f ~/.undercloud.end ]; then
			echo "Cant find ~/.undercloud.end .."
			echo "undercloud is not installed.."
		fi
		echo "#########################"
		echo "openstack undercloud install completed.."
		echo "next step: $0 images"
		exit
	fi
		## start overcloud

	if [ -z "$1" ]  || [ "$1" = "images" ]; then
		IMG_DIR=`dirname $0`/../images
		if [ ! -d "$IMG_DIR" ]; then
			echo "IMG_DIR[$IMG_DIR] no exist"
			exit 2
		fi
		. ~/stackrc || exit 1
		if [ ! -d ~/images ]; then
			mkdir ~/images
			for F in `ls -1 $IMG_DIR/*.tar`; do 
				echo "[$F] -> images/"
				tar -xpvf "$F"  -C ~/images/ || exit
			done
			set -x
			openstack overcloud image upload --image-path ~/images/
			openstack image list
			openstack subnet set --dns-nameserver 172.16.10.3  ctlplane-subnet
			[ -f /etc/bash_completion.d/openstack ] || openstack complete | sudo tee /etc/bash_completion.d/openstack > /dev/null


		fi
		echo "#########################"
		echo "openstack images uploaded .."
		echo "next step: $0 download"
		exit
	fi
	
	
	if [ ! -z "$1" ] &&  [ "$1" = "download" ]; then

	# remember DOCKER IP must be reachable from overcloud (in band)
	# IP="$(echo $LOCAL_IP | sed -e 's|/24$||g')"
	# DOCKER_DEST=$IP:8787
	# offboard docker
	DOCKER_DEST=10.10.1.5:5000
		### ====================== 
		. ~/stackrc || exit 1

		set -x
		[ -f /home/stack/local_registry_images.yaml ] || openstack overcloud container image prepare  --namespace=docker.io/tripleo$OSDIST \
--push-destination=${DOCKER_DEST} \
--tag-from-label {version}-{release} \
--output-env-file=/home/stack/overcloud_images_environment.yaml \
--output-images-file /home/stack/local_registry_images.yaml
	
		openstack overcloud container image upload  --config-file  /home/stack/local_registry_images.yaml --verbose
		echo "## container images downloaded.."
		echo "## should be ready for overcloud.."
		exit
	fi

