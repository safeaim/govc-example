#!/bin/bash
#
# The script that does the actual provisioning

export GOVC_DATACENTER="MyDC"
export template="rhel7-template"
export new_vm="govc-test01.example.org"
govc vm.clone -vm=$template -net="vlan_example" -datastore-cluster="datastore_example" -on=false -pool pool0_example -host esx-example.org -folder folder_example $new_vm
export CLOUD_CONFIG=$(gzip -c9 <cloud-config.yaml | base64)
export METADATA=$(sed 's~NETWORK_CONFIG~'"$(gzip -c9 <network.config.yaml | { base64 -w0 2>/dev/null || base64; } )"'~' <metadata.json | gzip -9 | { base64 -w0 2>/dev/null || base64; })
govc vm.change -vm $new_vm -e guestinfo.metadata="${METADATA}"
govc vm.change -vm $new_vm -e guestinfo.metadata.encoding=gzip+base64
govc vm.change -vm $new_vm -e guestinfo.userdata="${CLOUD_CONFIG}"
govc vm.change -vm $new_vm -e guestinfo.userdata.encoding=gzip+base64
