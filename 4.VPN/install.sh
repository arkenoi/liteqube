#!/bin/bash


. ../.lib/lib.sh
. ./settings-installer.sh
set -e
#set -x


if [ -z "${VPN_SSH}" -a -z "${VPN_OVPN}" ] ; then
    message "Please set at least one of 'VPN_SSH' or 'VPN_OVPN' in ${YELLOW}settings-installer.sh${PREFIX} to proceed"
    exit 1
fi
vm_fail_if_missing "${VM_CORE}"
vm_fail_if_missing "${VM_DVM}"
vm_fail_if_missing "${VM_KEYS}"

message "RECORDING SNAPSHOT FOR ${YELLOW}${VM_CORE}"
qvm-shutdown --force --wait ${VM_CORE}
mkdir -p /tmp/liteqube-rollback.4
qvm-volume info "${VM_CORE}:root" revisions|tail -1 >"/tmp/liteqube-rollback.4/snapshot-${VM_CORE}-root.id"
qvm-volume info "${VM_CORE}:private" revisions|tail -1 >"/tmp/liteqube-rollback.4/snapshot-${VM_CORE}-private.id"
message "MAKING ${YELLOW}dom0${PREFIX} CONFIG BACKUPS"
cp ${LQ_POLICYFILE} /tmp/liteqube-rollback.4/

vm_exists "${VM_VPN}" && qvm-shutdown --quiet --wait --force "${VM_VPN}" || vm_create "${VM_VPN}" "dispvm"
message "CONFIGURING ${YELLOW}${VM_VPN}"
vm_configure "${VM_VPN}" "pvh" 176 "${VM_FW_NET}" ''
qvm-prefs --quiet --set "${VM_VPN}" provides_network True
vm_exists "${VM_FW_NET}"|| qvm-prefs --quiet --default "${VM_VPN}" netvm

message "CONFIGURING ${YELLOW}${VM_CORE}"
qvm-start --quiet --skip-if-running "${VM_CORE}"
push_files "${VM_CORE}"
add_line "${VM_CORE}" "/etc/hosts" "127.0.0.1 ${VM_VPN}"
install_settings "${VM_VPN}"

message "CONFIGURING ${YELLOW}dom0"
push_files "dom0"
if [ -n "${VPN_SSH}" ] ; then
    setup_permissions "${VM_VPN}" xorg ssh
fi
if [ -n "${VPN_OVPN}" ] ; then
    setup_permissions "${VM_VPN}" xorg file password
fi
add_permission "SignalVPN" "${VM_VPN}" "dom0" "allow"
dom0_install_command lq-vpn
# TODO This is only needed until Base is updated
dom0_install_command lq-addkey

if [ -n "${VPN_SSH}" ] ; then
    message "CONFIGURING ${YELLOW}${VM_CORE}${PREFIX} FOR SSH VPN"
    push_command "${VM_CORE}" "apt-get -q -y install redsocks net-tools dnscrypt-proxy"
    push_from_dir "./default.ssh" "${VM_CORE}"

    message "PUSHING SSH FILES TO ${YELLOW}${VM_KEYS}"
    message "PUT ${YELLOW}id_rsa, id_rsa.pub, known_hosts${PREFIX} INTO ${YELLOW}./files.ssh${PREFIX} AND PRESS ENTER"
    read INPUT

    [ ! -e "./files.ssh/known_hosts" ] || cat "./files.ssh/known_hosts" | push_command "${VM_CORE}" "cat > /etc/protect/template.${VM_VPN}/home/user/.ssh/known_hosts"

    for FILE in ./files.ssh/id_rsa* ; do
        checksum_to_vm "${FILE}" "${VM_KEYS}" "/home/user/.ssh/$(basename "$FILE")"
    done

    push_command "${VM_KEYS}" "chmod 0600 /home/user/.ssh/*"
    push_command "${VM_KEYS}" "chown user:user /home/user/.ssh/*"
    push_command "${VM_CORE}" "chmod 0600 /etc/protect/checksum.${VM_KEYS}/home/user/.ssh/*"
    push_command "${VM_CORE}" "chown user:user /etc/protect/checksum.${VM_KEYS}/home/user/.ssh/*"
fi

if [ -n "${VPN_OVPN}" ] ; then
    message "CONFIGURING ${YELLOW}${VM_CORE}${PREFIX} FOR OPENVPN"
    push_command "${VM_CORE}" "apt-get -q -y install openvpn"
    push_from_dir "./default.ovpn" "${VM_CORE}"

    message "PUSHING OPENVPN CONFIG FILES TO ${YELLOW}${VM_KEYS}"
    message "PUT ZIP FILES WITH OPENVPN CONFIG INTO ${YELLOW}./files.ovpn${PREFIX} AND PRESS ENTER"
    read INPUT
    qvm-start --quiet --skip-if-running "${VM_KEYS}"
    for FILE in ./files.ovpn/*.zip ; do
        checksum_to_vm "${FILE}" "${VM_KEYS}" "/home/user/${VM_VPN}/$(basename "$FILE")"
    done
fi

message "CUSTOMISING INSTALLATION"
[ ! -x ./custom/custom.sh ] || . ./custom/custom.sh
message "DONE CUSTOMISING"

message "TERMINATING ${YELLOW}${VM_CORE}"
qvm-shutdown --quiet --wait --force "${VM_CORE}"

message "DONE!"
exit 0
