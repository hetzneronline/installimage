#!/bin/bash

#
# CoreOS specific functions
#
# (c) 2014-2023, Hetzner Online GmbH
#
# This file isn't ready for production!
#

# create partitons on the given drive
# create_partitions "DRIVE"
create_partitions() {
  touch "$FOLD/fstab"
  return 0
}

make_swraid() {
  return 0
}

mount_partitions() {
  return 0
}

make_lvm() {
  return 0
}

format_partitions() {
  return 0
}

# validate image with detached signature
#validate_image() {
#  # no detached sign found
#  return 2
#}

# extract image file to hdd
extract_image() {
  return 0
}

setup_network_config() {
  return 0
}

# generate_config_mdadm "NIL"
generate_config_mdadm() {
  return 0
}

# generate_new_ramdisk "NIL"
generate_new_ramdisk() {
  return 0
}

set_udev_rules() {
  return 0
}

# copy_mtab "NIL"
copy_mtab() {
  return 0
}

generate_new_sshkeys() {
  return 0
}

generate_ntp_config() {
  return 0
}

set_hostname() {
  export COREOS_CONFIG_HOSTNAME="$1"
}

setup_cpufreq() {
  return 0
}

generate_resolvconf() {
  return 0
}

generate_hosts() {
  return 0
}

generate_sysctlconf() {
  return 0
}

set_rootpassword() {
  export COREOS_CONFIG_PASSWORD="$2"
  return 0
}

# set sshd PermitRootLogin
set_ssh_rootlogin() {
  if [ -n "$1" ]; then
    export COREOS_SSH_PERMIT_ROOT_LOGIN="$1"
  else
    return 1
  fi
}

# copy_ssh_keys $OPT_SSHKEYS_URL
copy_ssh_keys() {
  return 0
}

# generate_config_grub <version>
generate_config_grub() {
  return 0
}

write_grub() {
  return 0
}

add_coreos_oem_scripts() {
  return 0
}

run_os_specific_functions() {
  #  apt-get update -y && apt-get install gcc g++ pkg-config libssl-dev libzstd-dev -y

  local ROOT_INDEX=""
  declare -a PART_LABEL
  for ((i = 1; i <= PART_COUNT; i++)); do
    if [ "${PART_MOUNT[$i]}" = "/" ] && [ "$ROOT_INDEX" = "" ]; then
      ROOT_INDEX="$i"
    fi
    PART_LABEL[$i]="$(echo "${PART_MOUNT[$i]}" | sed 's/^\///g' | sed 's|\/$||g' | sed 's/\//-/g')"
  done

  echo "ROOT_INDEX: $ROOT_INDEX"
  echo "${PART_MOUNT[@]}"

  local CRYPT_OTHER_PARTS="0"
  for ((i = 1; i <= PART_COUNT; i++)); do
    if [ "$i" != "$ROOT_INDEX" ] && [ "${PART_CRYPT[$i]}" = "1" ]; then
      CRYPT_OTHER_PARTS="1"
      break
    fi
  done

  BUTANE_CONFIG="/tmp/installimage.bu"
  {
    echo "variant: fcos"
    echo "version: 1.4.0"
    echo "passwd:"
    echo "  users:"
    echo "    - name: core"
    echo "      groups:"
    echo "        - wheel"
    echo "        - sudo"
    echo "      ssh_authorized_keys:"
    while read -r line; do
      if [ -n "$line" ]; then
        echo "        - $line"
      fi
    done <"$FOLD/authorized_keys"
    if [ "$SWRAID" = "1" ] || [ "$CRYPT" = "1" ]; then
      echo "boot_device:"
      if [ "$SWRAID" = "1" ]; then
        echo "  mirror:"
        echo "    devices:"
        echo "      - $DRIVE1"
        echo "      - $DRIVE2"
      fi
      if [ "${PART_CRYPT[$ROOT_INDEX]}" = "1" ]; then
        echo "  luks:"
        echo "    tpm2: true"
      fi
    fi
    echo "storage:"
    echo "  disks:"
    echo "    - device: $DRIVE1"
    echo "      partitions:"
    if [ "$SWRAID" = "1" ]; then
      echo "        - label: root-1"
      echo "          size_mib: ${PART_SIZE[$ROOT_INDEX]}"
      for ((i = 1; i <= PART_COUNT; i++)); do
        if [ "$i" != "$ROOT_INDEX" ]; then
          echo "        - label: ${PART_LABEL[$i]}-1"
          echo "          size_mib: ${PART_SIZE[$i]}"
        fi
      done
    else
      echo "        - label: root"
      echo "          number: 4"
      echo "          resize: true"
      echo "          size_mib: ${PART_SIZE[$ROOT_INDEX]}"
      for ((i = 1; i <= PART_COUNT; i++)); do
        if [ "$i" != "$ROOT_INDEX" ]; then
          echo "        - label: ${PART_LABEL[$i]}"
          echo "          size_mib: ${PART_SIZE[$i]}"
        fi
      done
    fi
    echo "    - device: $DRIVE2"
    echo "      partitions:"
    if [ "$SWRAID" = "1" ]; then
      echo "        - label: root-2"
      echo "          size_mib: ${PART_SIZE[$ROOT_INDEX]}"
      for ((i = 1; i <= PART_COUNT; i++)); do
        if [ "$i" != "$ROOT_INDEX" ]; then
          echo "        - label: ${PART_LABEL[$i]}-2"
          echo "          size_mib: ${PART_SIZE[$i]}"
        fi
      done
    fi
    if [ "$SWRAID" = "1" ]; then
      echo "  raid:"
      for ((i = 1; i <= PART_COUNT; i++)); do
        if [ "$i" != "$ROOT_INDEX" ]; then
          echo "    - name: ${PART_LABEL[$i]}"
          echo "      level: raid1"
          echo "      devices:"
          echo "        - /dev/disk/by-partlabel/${PART_LABEL[$i]}-1"
          echo "        - /dev/disk/by-partlabel/${PART_LABEL[$i]}-2"
        fi
      done
    fi
    if [ "$CRYPT_OTHER_PARTS" = "1" ]; then
      echo "  luks:"
      for ((i = 1; i <= PART_COUNT; i++)); do
        if [ "${PART_CRYPT[$i]}" = "1" ] && [ "$i" != "$ROOT_INDEX" ]; then
          echo "    - name: ${PART_LABEL[$i]}"
          echo "      label: ${PART_LABEL[$i]}"
          echo "      wipe_volume: true"
          echo "      device: /dev/disk/by-partlabel/${PART_LABEL[$i]}"
        fi
      done
    fi
    echo "  filesystems:"
    for ((i = 1; i <= PART_COUNT; i++)); do
      if [ "$i" != "$ROOT_INDEX" ]; then
        if [ "${PART_CRYPT[$i]}" = "1" ]; then
          echo "    - device: /dev/mapper/${PART_LABEL[$i]}"
        elif [ "$SWRAID" = "1" ]; then
          echo "    - device: /dev/md/${PART_LABEL[$i]}"
        else
          echo "    - device: /dev/disk/by-partlabel/${PART_LABEL[$i]}"
        fi
        echo "      format: ${PART_FS[$i]}"
        echo "      label: ${PART_LABEL[$i]}"
        echo "      wipe_filesystem: true"
        echo "      path: ${PART_MOUNT[$i]}"
        echo "      with_mount_unit: true"
      fi
    done
    cat <<EOF
  files:
  - path: /etc/hostname"
    mode: 0644"
    contents:"
      inline: $COREOS_CONFIG_HOSTNAME"
systemd:
  units:
    - name: rpm-ostree-countme.timer
      enabled: false
      mask: true
EOF
  } \
    >"$BUTANE_CONFIG"
  curl --request GET -sL \
       --url "https://github.com/coreos/butane/releases/download/v0.17.0/butane-$(uname -m)-unknown-linux-gnu"\
       --output "/usr/local/bin/butane"
  chmod +x /usr/local/bin/butane

  butane --strict --pretty "$BUTANE_CONFIG" >"/tmp/installimage.ign"

  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

  cargo install coreos-installer

  coreos-installer "$DRIVE1" -i "/tmp/installimage.ign" -s stable

  return 0
}

# vim: ai:ts=2:sw=2:et
