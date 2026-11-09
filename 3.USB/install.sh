#!/bin/bash


# Set to "True" if you will be connecting input devices to usb vm
USB_INPUT_DEVICES="True"

# Set to "True" to not require PCI device reset
USB_NO_STRICT_RESET="True"

# Set to "True" if you want to enable u2f and pkcs11
USB_SMARTCARD="True"

# p11-kit changed its RPC wire format in 0.25.6 without negotiating it (https://github.com/p11-glue/p11-kit/issues/733):
# a client whose p11-kit is on the other side of that release than debian-core's (0.25.5 on Debian 13) logs in and
# lists keys fine but fails at the first signing call. Fedora 42 and later templates are on the new side.
# Until the fix is released, a p11-kit of the version below is unpacked under /opt/liteqube/p11-kit-<version> in
# debian-core and liteqube.pkcs11 serves every client with the build speaking its own dialect. Leave the version
# empty to skip this. The .debs come from snapshot.debian.org (permanent URLs); sha256 sums are checked in dom0.
PKCS11_EXTRA_SERVER_VERSION="0.26.5"
PKCS11_EXTRA_SERVER_DEBS="
https://snapshot.debian.org/archive/debian/20260815T203404Z/pool/main/p/p11-kit/libp11-kit0_0.26.5-1_amd64.deb 7f6187247766dca57582c4fa327928fb612de3cd17a13786c1762c57357b4930
https://snapshot.debian.org/archive/debian/20260815T203404Z/pool/main/p/p11-kit/p11-kit_0.26.5-1_amd64.deb 418886fb719c2967bc827206d3e36433a8a25c7c306e0b9480f1e1d919bed033
"

# Set to "True" to install smartcard diagnostic tools (opensc-tool, pkcs11-tool, p11tool)
#USB_DEBUG="True"

# sys-usb vm name
SYS_USB="sys-usb"

USB_VM_MEMORY=256

#
# Space-separated list of qubes having access to smartcards
QUBES_SMARTCARD_CLIENTS="personal work"
SMARTCARD_MODCONFIG="
disable-in: gnome-calculator gnome-terminal
#enable-in: openssh-agent
"

#########################################################################
#       Do not edit code below unless you know what you are doing       #
#########################################################################


chmod +x ../.lib/lib.sh
. ../.lib/lib.sh
set -e

vm_fail_if_missing "${VM_CORE}"
vm_fail_if_missing "${VM_DVM}"
vm_fail_if_missing "${VM_XORG}"

mkdir -p /tmp/liteqube-rollback.3
qvm-shutdown --force --wait "${VM_CORE}"
qvm-volume config "${VM_CORE}:root" revisions_to_keep 10
qvm-volume config "${VM_CORE}:private" revisions_to_keep 10
message "RECORDING SNAPSHOT FOR ${YELLOW}${VM_CORE}"
qvm-volume info "${VM_CORE}:root" revisions|tail -1 >"/tmp/liteqube-rollback.3/snapshot-${VM_CORE}-root.id"
qvm-volume info "${VM_CORE}:private" revisions|tail -1 >"/tmp/liteqube-rollback.3/snapshot-${VM_CORE}-private.id"
message "MAKING ${YELLOW}dom0${PREFIX} CONFIG BACKUPS"
cp /etc/qubes/policy.d/50-config-input.policy /tmp/liteqube-rollback.3/
cp /etc/qubes/policy.d/50-config-u2f.policy /tmp/liteqube-rollback.3/
cp ${LQ_POLICYFILE} /tmp/liteqube-rollback.3/

vm_create "${VM_USB}" dispvm
vm_configure ${VM_USB} hvm ${USB_VM_MEMORY} '' '' ''

message "STARTING ${YELLOW}${VM_CORE}"
qvm-start --quiet --skip-if-running "${VM_CORE}"


message "CONFIGURING ${YELLOW}${VM_CORE}"
push_command ${VM_CORE} "apt update" 
install_packages ${VM_CORE} usbguard qubes-usb-proxy
add_line "${VM_CORE}" "/etc/hosts" "127.0.1.1       ${VM_USB}"
push_files "${VM_CORE}"
for SERVICE in usbguard usbguard-dbus ; do
    push_command "${VM_CORE}" "systemctl stop ${SERVICE} >/dev/null 2>&1" >/dev/null 2>&1 || true
    push_command "${VM_CORE}" "systemctl disable ${SERVICE} >/dev/null 2>&1" >/dev/null 2>&1 || true
done


message "CONFIGURING ${YELLOW}dom0"
push_files "dom0"
sudo qubes-dom0-update -y --console --show-output qubes-usb-proxy-dom0
setup_permissions "${VM_USB}" xorg
add_permission "SignalStorage" "${VM_USB}" "dom0" "allow"

if [ x"${USB_INPUT_DEVICES}" = x"True" ] ; then
    message "CONFIGURING USB INPUT IN ${YELLOW}${VM_CORE}"
    install_packages "${VM_CORE}" "qubes-input-proxy-sender"
    message "CONFIGURING USB INPUT IN ${YELLOW}dom0"
    sudo qubes-dom0-update --console --show-output -y qubes-input-proxy
else
    sudo rm -f /etc/qubes/policy.d/50-config-input.policy
fi

qvm-ls --class TemplateVM --fields NAME|tail -n +2|while read TEMPLATE; do
    push_command "${TEMPLATE}" "systemctl is-enabled qubes-ctappoxy@${SYS_USB}" && (
    echo "Found ctap proxy on ${TEMPLATE} to ${SYS_USB}, redirecting to ${VM_SC}";
    push_command "${TEMPLATE}" "systemctl disable qubes-ctappoxy@${SYS_USB}";
    push_command "${TEMPLATE}" "systemctl enable qubes-ctappoxy@${VM_SC}"; )
    qvm-shutdown --quiet --wait --force "${TEMPLATE}"
done

if [ x"${USB_SMARTCARD}" = x"True" ] ; then
    vm_exists "${VM_SC}" || ( vm_create "${VM_SC}" "dispvm" && vm_configure "${VM_SC}" "pvh" 256 '' '' )
    vm_fail_if_missing "${VM_SC}"
    install_packages "${VM_CORE}" p11-kit pcscd opensc-pkcs11 python3-fido2 qubes-ctap
    if [ x"${USB_DEBUG}" = x"True" ] ; then
        install_packages "${VM_CORE}" opensc gnutls-bin
    fi
    add_line "${VM_CORE}" "/usr/lib/systemd/system/pcscd.service" "WantedBy=smartcard.target"
    push_command "${VM_CORE}" "systemctl daemon-reload" 
    push_command "${VM_CORE}" "systemctl enable pcscd.service" 
    qvm-service -e ${VM_SC} liteqube-pkcs11

    if [ -n "${PKCS11_EXTRA_SERVER_VERSION}" ] ; then
        message "INSTALLING p11-kit ${YELLOW}${PKCS11_EXTRA_SERVER_VERSION}${PREFIX} SERVER BUILD TO ${YELLOW}${VM_CORE}"
        EXTRA_DIR="/opt/liteqube/p11-kit-${PKCS11_EXTRA_SERVER_VERSION}"
        push_command "${VM_CORE}" "rm -rf ${EXTRA_DIR} ; mkdir -p ${EXTRA_DIR}"
        echo "${PKCS11_EXTRA_SERVER_DEBS}" | while read -r DEB_URL DEB_SHA256 ; do
            [ -n "${DEB_URL}" ] || continue
            DEB_FILE="./files/p11-kit/$(basename "${DEB_URL}")"
            if ! echo "${DEB_SHA256}  ${DEB_FILE}" | sha256sum --check --status 2>/dev/null ; then
                message "DOWNLOADING ${YELLOW}$(basename "${DEB_URL}")"
                dom0_download "${DEB_URL}" "${DEB_FILE}"
                if ! echo "${DEB_SHA256}  ${DEB_FILE}" | sha256sum --check --status ; then
                    rm -f "${DEB_FILE}"
                    message "ERROR: CHECKSUM MISMATCH FOR ${YELLOW}${DEB_URL}${PREFIX}, NOT INSTALLING IT"
                    exit 1
                fi
            fi
            file_to_vm "${DEB_FILE}" "${VM_CORE}" "/tmp/liteqube-p11-kit.deb"
            push_command "${VM_CORE}" "dpkg -x /tmp/liteqube-p11-kit.deb ${EXTRA_DIR} && rm -f /tmp/liteqube-p11-kit.deb"
        done
        # only the remote helper and its library are used, see liteqube.pkcs11
        push_command "${VM_CORE}" "rm -rf ${EXTRA_DIR}/usr/share ${EXTRA_DIR}/usr/bin ${EXTRA_DIR}/usr/libexec/p11-kit/p11-kit-server"
    fi
    for VM in ${QUBES_SMARTCARD_CLIENTS} ; do
   	add_permission "pkcs11" "${VM}" "${VM_SC}" "allow target=${VM_SC}"
    done
    message "INSTALLING ${YELLOW}p11-kit${PREFIX} TO TEMPLATES"
    sed -e "s/TARGET/${VM_SC}/" <"./files/remote-pkcs11.module.in" >"./files/remote-pkcs11.module"
    echo "${SMARTCARD_MODCONFIG}" >>"./files/remote-pkcs11.module"
    TEMPLATES_MODIFIED=""
    for VM in ${QUBES_SMARTCARD_CLIENTS} ; do
        qvm-service -e ${VM} remote-pkcs11
        qvm-service -e ${VM} qubes-ctapproxy
        TEMPLATE="$(vm_find_template "${VM}")"
        if ! echo "${TEMPLATES_MODIFIED}" | grep "^${VM}$$" >/dev/null 2>&1 ; then
            TEMPLATE_TYPE="$(vm_type "${TEMPLATE}")"
       	    case "${TEMPLATE_TYPE}" in
       	    debian)
       	        push_command "${TEMPLATE}" "apt-get -y install p11-kit ncat"
                push_command "${TEMPLATE}" "systemctl disable qubes-ctapproxy@${SYS_USB}"
                push_command "${TEMPLATE}" "systemctl enable qubes-ctapproxy@${VM_SC}"
                file_to_vm "./files/remote-pkcs11.module" "${TEMPLATE}" "/usr/share/p11-kit/modules/remote-pkcs11.module"
            ;;
            fedora)
                push_command "${TEMPLATE}" "dnf -y install qubes-ctap p11-kit p11-kit-client nmap-ncat"
                push_command "${TEMPLATE}" "systemctl disable qubes-ctapproxy@${SYS_USB}"
                push_command "${TEMPLATE}" "systemctl enable qubes-ctapproxy@${VM_SC}"
                file_to_vm "./files/remote-pkcs11.module" "${TEMPLATE}" "/usr/share/p11-kit/modules/remote-pkcs11.module"
            ;;
            *)
                message "ERROR: DON'T KNOW HOW TO HANDLE ${YELLOW}${TEMPLATE_TYPE}"
            ;;
            esac
            qvm-shutdown --quiet --wait --force "${TEMPLATE}"
            TEMPLATES_MODIFIED="${TEMPLATES_MODIFIED}${ENTER}${VM}"
        fi
    done
fi


message "CUSTOMISING INSTALLATION"
if [ -x ./custom/custom.sh ] ; then
    . ./custom/custom.sh
fi
message "DONE CUSTOMISING"


message "RESTARTING ${YELLOW}${VM_CORE}"
qvm-shutdown --quiet --wait --force "${VM_CORE}"
qvm-start --quiet --skip-if-running "${VM_CORE}"
sleep 3
push_command "${VM_CORE}" "rm -rf /rw/QUARANTINE >/dev/null 2>&1"
qvm-shutdown --quiet --wait --force "${VM_CORE}"


if vm_exists "${SYS_USB}" ; then
    message "ATTACHING ${YELLOW}${SYS_USB}${PREFIX} DEVICES TO ${YELLOW}${VM_USB}"
    qvm-shutdown --quiet --wait --force "${SYS_USB}"
    if [ x"${USB_NO_STRICT_RESET}" = x"True" ] ; then
        OPTIONS="--option no-strict-reset=true"
    fi
    qvm-pci list --assignments | grep "${SYS_USB}" | cut -f 1 -d " " | uniq| while read DEVICE ; do
        message "ATTACHING ${DEVICE}"
        qvm-pci attach "${VM_USB}" "${DEVICE}" --persistent ${OPTIONS} || true
    done

    message "STARTING ${YELLOW}${VM_USB}"
    qvm-prefs --set "${VM_USB}" autostart True
    qvm-prefs --default "${SYS_USB}" autostart
    sleep 5
    qvm-start --quiet --skip-if-running "${VM_USB}"
else
    if qvm-pci | grep "${VM_USB}" >/dev/null 2>&1 ; then
        message "STARTING ${YELLOW}${VM_USB}"
        qvm-prefs --set "${VM_USB}" autostart True
        qvm-start --quiet --skip-if-running "${VM_USB}" || true
    else
        message "NO DEVICES ATTACHED TO ${YELLOW}${VM_USB}${PREFIX}, PLEASE ATTACH AND START ${YELLOW}${VM_USB}"
    fi
fi

if [ -e "/etc/qubes/policy.d/50-config-input.policy" ] ; then
    replace_text dom0 "/etc/qubes/policy.d/50-config-input.policy" "${SYS_USB}" "${VM_USB}" 
else
    message "Input policy file not found!"
fi
if [ -e "/etc/qubes/policy.d/50-config-u2f.policy" ] ; then
    replace_text dom0 "/etc/qubes/policy.d/50-config-u2f.policy" "${SYS_USB}" "${VM_USB}"
else
    message "U2F policy file not found!"
fi
message "DONE!"
exit 0
