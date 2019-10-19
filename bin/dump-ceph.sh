#!/bin/bash
. ~stack/stackrc || exit



# (undercloud) [stack@undercloud tripleo]$  mistral task-get -c Name -c State -f value 47893d3b-ad58-4b81-9418-91a528981a90
# collect_puppet_hieradata
# SUCCESS

# (undercloud) [stack@undercloud tripleo]$ mistral task-get -c Name -c State -f shell 47893d3b-ad58-4b81-9418-91a528981a90
# name="collect_puppet_hieradata"
# state="SUCCESS"



WORKFLOW='tripleo.storage.v1.ceph-install'
UUID=$(mistral execution-list | grep $WORKFLOW | awk {'print $2'} | tail -1)

## Then use the ID to examine each task:
for TASK_ID in $(mistral task-list $UUID | awk {'print $2'} | egrep -v 'ID|^$'); do
    # echo "############  task-get $TASK_ID ###############"
    # mistral task-get $TASK_ID
    # mistral task-get -c Name -c State  $TASK_ID
    echo -n "## TASK_ID[$TASK_ID]="
    RES="`mistral task-get -c Name -c State -f shell  $TASK_ID`"
    NAME="`echo $RES | sed -e 's|.*="\(.*\)" .*="\(.*\)"$|\1|g'`"
    STATE="`echo $RES | sed -e 's|.*="\(.*\)" .*="\(.*\)"$|\2|g'`"
    echo "NAME[$NAME]=STATE[$STATE]"
    [ "x$STATE" = "xSUCCESS" ] && continue

    echo "############  task-get-result $TASK_ID ###############"
    mistral task-get-result $TASK_ID | jq . | sed -e 's/\\n/\n/g' -e 's/\\"/"/g'
    echo "######################################################"
done
