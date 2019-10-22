# tripleNo
## undercloud - new vm
```
virt-install --connect qemu:///system --vnc --vnclisten=0.0.0.0 \
-r 32768 --vcpus=16 \
--disk pool=NFS_TANGO,size=40,format=qcow2 \
--network=bridge=br0 \
--network=bridge=br5 \
--network=bridge=br4 \
--location=nfs:cirrus:/data/centos7/  \
--extra-args "inst.ks=http://kickstart.shopsmart.au.nu/cgi-bin/ks.cgi?HOSTNAME=undercloud&TEMPLATE=centos7" \
--name undercloud
```

## configure br-ex (eth2)
```
/bin/cp -p undercloud/{ifcfg-eth2,ifcfg-br-ex,ifcfg-vlan10} /etc/sysconfig/network-scripts/
```

## undercloud prep (root)
* configs: eth1 (provisioning NIC)
* installs python2-tripleo-repos.rpm
```
# run as 'root' user 
undercloud/undercloud.sh
reboot
```

## undercloud install (stack)
* installs undercloud
* upload (local) ironic-agent and overcloud-full images
```
## run as 'stack' user
undercloud/undercloud.sh undercloud
undercloud/undercloud.sh images

```
## prepare for overcloud image download
* add inscure reg to docker  (--insecure-registry 10.10.1.5:5000 )
* then reboot : update stack user perms / restart docker / brings up br-ex
```
sudo vi /etc/sysconfig/docker
sudo reboot
```
## get overcloud images
```
# run as 'stack' user
undercloud/undercloud.sh download
```

## covercloud config
```
cat > ~/.overcloud.conf  <<EOF
## OVN -take 1 
export DOCKER_DEST=10.10.1.5:5000
export OSDIST=queens
#
export EXT_NIC=eth2
export EXT_BR=br-ex
export EXT_VLAN=10
export EXT_GW=172.16.210.1
export DOMS="controller0 controller1 controller2 compute0 compute1"
export ANSWER_FILE=~/templates/answers/3-controller-ovn.yaml
export DOWNLOAD_OVN=y
EOF
```

## install overcloud
```
overcloud/overcloud.sh

```

## memcached still blocker
```
## on all controllers
Oct 17 16:04:38 controller2 kernel: IN=vlan13 OUT= MAC=9a:13:4e:1d:06:da:3e:6e:99:7d:8f:f0:08:00 SRC=172.16.213.10 DST=172.16.213.12 LEN=60 TOS=0x00 PREC=0x00 TTL=64 ID=41202 DF PROTO=TCP SPT=35806 DPT=11211 WINDOW=29200 RES=0x00 SYN URGP=0 
Oct 17 16:04:39 controller2 kernel: IN=vlan13 OUT= MAC=9a:13:4e:1d:06:da:3e:6e:99:7d:8f:f0:08:00 SRC=172.16.213.10 DST=172.16.213.12 LEN=60 TOS=0x00 PREC=0x00 TTL=64 ID=41203 DF PROTO=TCP SPT=35806 DPT=11211 WINDOW=29200 RES=0x00 SYN URGP=0 
```
* add firewall rule
```
iptables -I INPUT 5  -i vlan13 -p tcp --dport 11211 -j ACCEPT  -m state --state NEW -m comment --comment "added memcached"
```
