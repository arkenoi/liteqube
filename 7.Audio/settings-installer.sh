#!/bin/sh

# Space-separated list of qubes having access to aoudio playback
QUBES_WITH_SOUND="core-rdp dvm-chrome dvm-chrome-tor my-games"

# Set to "True" to not require PCI device reset
AUDIO_NO_STRICT_RESET="True"

# Qube that currently provides audio service
ORIGINAL_VM_AUDIO="dom0"

# Space-separated list of firmware packages your sound hardware needs, e.g. "firmware-sof-signed"
# for Intel laptops from Tiger Lake on. Leave empty if the card works without extra firmware.
AUDIO_FIRMWARE_PACKAGES=""
