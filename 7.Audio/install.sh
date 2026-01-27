#!/bin/sh


. ../.lib/lib.sh
. ./settings-installer.sh
set -e
#set -x

vm_fail_if_missing "${VM_CORE}"
vm_fail_if_missing "${VM_DVM}"

message "RECORDING SNAPSHOT FOR ${YELLOW}${VM_CORE}"
qvm-shutdown --force --wait ${VM_CORE}
mkdir -p /tmp/liteqube-rollback.7
qvm-volume info "${VM_CORE}:root" revisions|tail -1 >"/tmp/liteqube-rollback.7/snapshot-${VM_CORE}-root.id"
qvm-volume info "${VM_CORE}:private" revisions|tail -1 >"/tmp/liteqube-rollback.7/snapshot-${VM_CORE}-private.id"
message "MAKING ${YELLOW}dom0${PREFIX} CONFIG BACKUPS"
cp ${LQ_POLICYFILE} /tmp/liteqube-rollback.7/

vm_exists "${VM_AUDIO}" && qvm-shutdown --quiet --wait --force "${VM_AUDIO}" || vm_create "${VM_AUDIO}" "dispvm"
vm_configure "${VM_AUDIO}" "hvm" 208 '' ''
qvm-prefs --set "${VM_AUDIO}" autostart True


message "CONFIGURING ${YELLOW}${VM_CORE}"
install_packages "${VM_CORE}" pipewire-qubes pulsemixer qubes-gui-daemon-pulseaudio
push_files "${VM_CORE}"
push_command "${VM_CORE}" "adduser user audio 2>/dev/null 1>&2"
install_settings "${VM_AUDIO}"


message "CONFIGURING ${YELLOW}dom0"
push_files "dom0"
setup_permissions "${VM_AUDIO}" xorg
add_permission "SignalSound" "${VM_AUDIO}" "dom0" "allow"
add_line dom0 "${LQ_POLICYFILE}" "admin.Events	*	${VM_AUDIO}	@adminvm	allow target=@adminvm"
add_line dom0 "${LQ_POLICYFILE}" "admin.vm.List	*	${VM_AUDIO}	@adminvm	allow target=@adminvm"
add_line dom0 "${LQ_POLICYFILE}" "admin.vm.property.Get *	${VM_AUDIO}	@adminvm	allow target=@adminvm"
for VM in ${QUBES_WITH_SOUND} ; do
    add_line dom0 "${LQ_POLICYFILE}" "admin.Events	*	${VM_AUDIO}	${VM}	allow target=@adminvm"
    add_line dom0 "${LQ_POLICYFILE}" "admin.vm.List	*	${VM_AUDIO}	${VM}	allow target=@adminvm"
    add_line dom0 "${LQ_POLICYFILE}" "admin.vm.property.Get	*	${VM_AUDIO}	${VM}	allow target=@adminvm"
    vm_exists "${VM}" && qvm-prefs "${VM}" audiovm "${VM_AUDIO}"
done
dom0_install_command lq-volume
dom0_install_command lq-mic


message "ATTACHING AUDIO DEVICES TO ${YELLOW}${VM_AUDIO}"
for DEVICE in $(qvm-pci | grep -ie Audio -ie Sound | cut -d' ' -f1); do
    [ x"${AUDIO_NO_STRICT_RESET}" = x"True" ] && OPTIONS="--option no-strict-reset=true"
    qvm-pci attach "${VM_AUDIO}" "${DEVICE}" --persistent ${OPTIONS} || true
done


if [ -x ./custom/custom.sh ] ; then
    message "CUSTOMISING INSTALLATION"
    . ./custom/custom.sh
    message "DONE CUSTOMISING"
fi


message "TERMINATING ${YELLOW}${VM_CORE}"
qvm-shutdown --quiet --wait --force "${VM_CORE}"
qvm-start --quiet --skip-if-running "${VM_AUDIO}"


message "DONE!"
exit 0
