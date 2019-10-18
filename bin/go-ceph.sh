#!/bin/bash
BASEDIR="`( cd $(dirname $0)/.. && pwd )`"
echo "BASEDIR=[$BASEDIR]"
. ${BASEDIR}/bin/prompt.inc || exit 1

prompt "REALY install ceph overcloud.."
set -x
sudo yum -y install python-pip ceph-ansible
sudo pip install ansible==2.6.17
ansible --version
ANSVER="$(ansible --version | awk '/^ansible/ { print $2 }')"
echo "ANSVER=[$ANSVER]"
[ "x$ANSVER" = "x2.6.17" ] || abort "ansiblever needs to be 2.6.17"
rpm -q ceph-ansible || abort "ceph-ansible not installed"

cat > ~/.overcloud.conf  <<EOF
## take 3 - ceph
export EXT_NIC=eth2
export EXT_BR=br-ex
export EXT_VLAN=10
export EXT_GW=172.16.210.1
export DOMS="controller0 controller1 controller2 compute0 compute1 ceph0 ceph1 ceph2"
export ANSWER_FILE=templates/answers/3-controller-3-ceph.yaml
export CEPH=y
EOF

echo "now run: overcloud/overcloud.sh"
