#!/usr/bin/env bash
# Description: Run on your host to encrypt the lvm partition
#
set -euo pipefail

LVM_PARTITION="${:LVM_PARTITION:-/dev/nvme0n1p5}"
LVM_DISK_NAME="${LVM_DISK_NAME:-openebs-crypt}"

echo "Use your default password to encrypt the disk"

sudo cryptsetup open $LVM_PARTITION $LVM_DISK_NAME

