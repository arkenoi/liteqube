#!/bin/sh

chmod +x ../.lib/lib.sh
. ../.lib/lib.sh
SYS_USB="sys-usb"

qvm-shutdown --quiet --wait --force "${VM_USB}"

qvm-start --quiet --skip-if-running "${SYS_USB}"
qvm-prefs --set "${SYS_USB}" autostart True
qvm-prefs --set "${SYS_USB}" autostart True

sed -i "s/${VM_USB}/${SYS_USB}/g" /etc/qubes/policy.d/50-config-input.policy
qvm-remove --force "${VM_USB}"
