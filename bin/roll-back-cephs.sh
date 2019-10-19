#!/bin/bash
BASEDIR="`( cd $(dirname $0)/.. && pwd )`"
echo "BASEDIR=[$BASEDIR]"
. ${BASEDIR}/bin/prompt.inc || exit 1

[ "`hostname`" = "dl380.shopsmart.au.nu" ] || abort "must be run on hypervisor"

prompt "Abot to roll back overcloud / dete ceph nodes"

prompt "stop all nodes"
for D in undercloud controller0 controller1 controller2 compute0 compute1 ceph0 ceph1 ceph2; do virsh destroy $D; done

prompt "roll back undercloud"
virsh snapshot-revert --domain undercloud --snapshotname images_downloaded && virsh start undercloud

prompt "rebuild cephs.."
export SKIP_PROMPT=y
for DOM in ceph0 ceph1 ceph2; do
/bin/rm ${BASEDIR}/data/xml/${DOM}.xml
/bin/rm ${BASEDIR}/data/json/${DOM}.json
virsh undefine --remove-all-storage ${DOM}
${BASEDIR}/bin/vm-ctl.sh mkdisk ${DOM} "50G 20G 20G 20G"
${BASEDIR}/bin/vm-ctl.sh mkxml ${DOM} 'br5 br6 br7 br4' 8 17000
done

${BASEDIR}/bin/vm-ctl.sh mkjson ceph0 dl380 6008 br5
${BASEDIR}/bin/vm-ctl.sh mkjson ceph1 dl380 6009 br5
${BASEDIR}/bin/vm-ctl.sh mkjson ceph2 dl380 6010 br5

