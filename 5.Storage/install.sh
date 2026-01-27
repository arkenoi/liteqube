#!/bin/bash


# Create iSCSI qube, anything except True will skip vm creation
ISCSI_VM="True"


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

message "RECORDING SNAPSHOT FOR ${YELLOW}${VM_CORE}"
qvm-shutdown --force --wait ${VM_CORE}
mkdir -p /tmp/liteqube-rollback.5
qvm-volume info "${VM_CORE}:root" revisions|tail -1 >"/tmp/liteqube-rollback.5/snapshot-${VM_CORE}-root.id"
qvm-volume info "${VM_CORE}:private" revisions|tail -1 >"/tmp/liteqube-rollback.5/snapshot-${VM_CORE}-private.id"
message "MAKING ${YELLOW}dom0${PREFIX} CONFIG BACKUPS"
cp ${LQ_POLICYFILE} /tmp/liteqube-rollback.5/

message "CONFIGURING ${YELLOW}${VM_CORE}"
qvm-start --quiet --skip-if-running "${VM_CORE}"
push_files "${VM_CORE}"
install_packages "${VM_CORE}" "lvm2 cryptsetup-bin"
add_line "${VM_CORE}" "/etc/hosts" "127.0.1.1       ${VM_DECRYPT}"
for SERVICE in dm-event.socket blk-availability lvm2-lvmpolld.socket lvm2-monitor systemd-pstore ; do
    push_command "${VM_CORE}" "systemctl stop ${SERVICE} >/dev/null 2>&1" >/dev/null 2>&1 || true
    push_command "${VM_CORE}" "systemctl disable ${SERVICE} >/dev/null 2>&1" >/dev/null 2>&1 || true
done


message "CONFIGURING ${YELLOW}dom0"
[ -x /bin/dialog ] || sudo qubes-dom0-update --console --show-output -y dialog
setup_permissions "${VM_DECRYPT}" xorg password
add_permission "SignalStorage" "${VM_DECRYPT}" "dom0" "allow"
dom0_command lq-storage

vm_create "${VM_DECRYPT}" "dispvm"
vm_configure "${VM_DECRYPT}" "pvh" "1024" "" 

if [ x"${ISCSI_VM}" = x"True" ] ; then

    if ! vm_exists "${VM_FW_NET}" ; then
        message "ERROR: ${YELLOW}${VM_FW_NET}${PREFIX} NOT FOUND, PLEASE RUN NETWORK INSTALL"
        exit 1
    fi

    ISCSI_DEFAULTS="$(cd ./files/open-iscsi ; find . -name default -type f | tail -n 1 ; cd ../..)"

    if [ x"${ISCSI_DEFAULTS}" = x"" ] ; then
	message "NO ISCSI CONFIGURATION FOUND, SKIPPING ${YELLOW}${VM_ISCSI}${PREFIX} CONFIGURATION"
        exit 1
    fi
    vm_create "${VM_ISCSI}" "dispvm"
    vm_configure "${VM_DECRYPT}" "pvh" "256" "${VM_FW_NET}" 

    message "CONFIGURING ${YELLOW}${VM_CORE}"
    push_command "${VM_CORE}" "apt-get -q -y install open-iscsi ethtool"
    add_line "${VM_CORE}" "/etc/hosts" "127.0.1.1       ${VM_ISCSI}"
    push_from_dir "./default.iscsi" "${VM_CORE}"
    for SERVICE in open-iscsi iscsid ; do
        push_command "${VM_CORE}" "systemctl stop ${SERVICE} >/dev/null 2>&1" >/dev/null 2>&1 || true
        push_command "${VM_CORE}" "systemctl disable ${SERVICE} >/dev/null 2>&1" >/dev/null 2>&1 || true
    done


    message "CONFIGURING ${YELLOW}dom0"
    setup_permissions "${VM_ISCSI}" xorg file
    add_permission "SignalStorage" "${VM_ISCSI}" "dom0" "allow"

    message "CONFIGURING ISCSI SERVICE IN ${YELLOW}${VM_ISCSI}"
    qvm-start --quiet --skip-if-running "${VM_KEYS}"
    checksum_to_vm "./files/open-iscsi/${ISCSI_DEFAULTS}" "${VM_KEYS}" "/home/user/${VM_ISCSI}/default"
    push_command "${VM_CORE}" "chown -R user:user /etc/protect/checksum.${VM_KEYS}/home/user || true"
    tar c -C "./files/open-iscsi" --exclude "default" . | push_command "${VM_CORE}" "tar x -C \"/etc/iscsi\""
    push_command "${VM_CORE}" "chown -R root:root /etc/iscsi 2>/dev/null"
    push_command "${VM_CORE}" "rm -f \"/etc/iscsi/${ISCSI_DEFAULTS}\""
    push_command "${VM_CORE}" "ln -s \"/run/liteqube/iscsi-default\" \"/etc/iscsi/${ISCSI_DEFAULTS}\""
    qvm-shutdown --quiet --wait --force "${VM_KEYS}"

fi # ISCSI


message "CUSTOMISING INSTALLATION"
if [ -x ./custom/custom.sh ] ; then
    . ./custom/custom.sh
fi
message "DONE CUSTOMISING"


message "TERMINATING ${YELLOW}${VM_CORE}"
qvm-shutdown --quiet --wait --force "${VM_CORE}"


message "DONE!"
exit 0
