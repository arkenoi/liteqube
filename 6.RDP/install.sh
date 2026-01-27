#!/bin/bash


# Space-separated remote connection apps to install. Currently TightVNC and xfreerdp3 are supported
REMOTE_APPS="freerdp3-x11 xtightvncviewer"


#########################################################################
#       Do not edit code below unless you know what you are doing       #
#########################################################################


chmod +x ../.lib/lib.sh
. ../.lib/lib.sh
set -e

vm_fail_if_missing "${VM_CORE}"
vm_fail_if_missing "${VM_DVM}"
vm_fail_if_missing "${VM_XORG}"
vm_fail_if_missing "${VM_KEYS}"

if ! vm_exists "${VM_FW_NET}" ; then
    message "ERROR: ${YELLOW}${VM_FW_NET}${PREFIX} NOT FOUND, PLEASE RUN NETWORK INSTALL"
    exit 1
fi

message "RECORDING SNAPSHOT FOR ${YELLOW}${VM_CORE}"
qvm-shutdown --force --wait ${VM_CORE}
mkdir -p /tmp/liteqube-rollback.6
qvm-volume info "${VM_CORE}:root" revisions|tail -1 >"/tmp/liteqube-rollback.6/snapshot-${VM_CORE}-root.id"
qvm-volume info "${VM_CORE}:private" revisions|tail -1 >"/tmp/liteqube-rollback.6/snapshot-${VM_CORE}-private.id"
message "MAKING ${YELLOW}dom0${PREFIX} CONFIG BACKUPS"
cp ${LQ_POLICYFILE} /tmp/liteqube-rollback.6/

vm_create "${VM_RDP}" "dispvm"
vm_configure "${VM_RDP}" "pvh" "384" "${VM_FW_NET}"
qvm-prefs --quiet --set "${VM_RDP}" provides_network True

message "CONFIGURING ${YELLOW}${VM_CORE}"
qvm-start --quiet --skip-if-running "${VM_CORE}"
add_line "${VM_CORE}" "/etc/hosts" "127.0.1.1       ${VM_RDP}"
push_files "${VM_CORE}"
install_packages "${VM_CORE}" ${REMOTE_APPS} pipewire-qubes

message "CONFIGURING ${YELLOW}dom0"
setup_permissions "${VM_RDP}" xorg password ssh

dom0_command lq-remote


message "CUSTOMISING INSTALLATION"
if [ -x ./custom/custom.sh ] ; then
    . ./custom/custom.sh
fi
message "DONE CUSTOMISING"


message "TERMINATING ${YELLOW}${VM_CORE}"
qvm-shutdown --quiet --wait --force "${VM_CORE}"


message "DONE!"
exit 0
