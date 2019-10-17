#!/bin/bash

CERTFILE=/etc/pki/ca-trust/source/anchors/cm-local-ca.pem
TEMPLATE=`dirname $0`/../overcloud/inject-trust-anchor.template
ls $CERTFILE > /dev/null || exit
ls $TEMPLATE > /dev/null || exit

## --- static header
	cat $TEMPLATE | sed  -ne '0,/^%%CERT%%/p' | grep -v ^%%CERT%%

## --- insert indented CERT
	cat $CERTFILE | awk '
BEGIN{ gocert = 0; }
/-----BEGIN CERTIFICATE-----/	{ gocert = 1; } 
				{	if (gocert==1) { print("    " $0 ); } }
/-----END CERTIFICATE-----/	{ gocert = 0; }
'

## --- static tail
	cat $TEMPLATE | sed  -ne '/^%%CERT%%/,$p' | grep -v ^%%CERT%%
