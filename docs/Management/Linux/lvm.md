---
title: LVM
order: 10
---

# Local Volume Management (LVM)

[LVM](https://en.wikipedia.org/wiki/Logical_volume_management) is used to manage local volumes.

## Requirements

```bash
# Install necessary tools if missing
sudo apt update
sudo apt install -y cryptsetup lvm2
```

## Encrypt the partition

Make sure you have an empty partition (without filesystem) ready.

```bash
PARTITION=/dev/nvme0n1p5
DISK_NAME=openebs-crypt
# Initialize LUKS on the partition
sudo cryptsetup luksFormat $PARTITION
# Open the encrypted partition
sudo cryptsetup open $PARTITION $DISK_NAME
```

## Create LVM

```bash
VG_NAME=openebs-vg
# Create a physical volume
sudo pvcreate /dev/mapper/$DISK_NAME
# Create a volume group
sudo vgcreate $VG_NAME /dev/mapper/$DISK_NAME

# Verify
sudo pvs
sudo vgs
```

## Load required kernel modules

```bash
modules=(dm_mod dm_thin_pool dm_snapshot dm_mirror dm_crypt)
for mod in "${modules[@]}"; do
  if ! lsmod | grep -q "^${mod}"; then
    sudo modprobe "$mod"
    echo "$mod" | sudo tee -a /etc/modules-load.d/openebs-lvm.conf > /dev/null
  fi
done
```

> **Note**  
> This is done automatically with the [`setup_server.sh`](/Management/Scripts/setup_server.sh) script.


# Resources

* [Manpage](https://manpages.debian.org/jessie/lvm2/lvm.8.en.html)
* [Ubuntu Guide](https://documentation.ubuntu.com/server/how-to/storage/manage-logical-volumes/#manage-logical-volumes)
* [Wikipedia](https://en.wikipedia.org/wiki/Logical_volume_management)

