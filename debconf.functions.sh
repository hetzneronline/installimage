#!/usr/bin/env bash

#
# debconf functions
#
# (c) 2018, Hetzner Online GmbH
#

debconf_set() {
  debug "# debconf set $@"
  echo "$@" | execute_chroot_command debconf-set-selections
}

debconf_set_grub_install_devices() {
  {
    echo 'KERNEL=="nvme*[0-9]n*[0-9]", ATTR{wwid}=="?*", SYMLINK+="disk/by-id/nvme-$attr{wwid}"'
    echo 'KERNEL=="nvme*[0-9]n*[0-9]p*[0-9]", ENV{DEVTYPE}=="partition", ATTRS{wwid}=="?*", SYMLINK+="disk/by-id/nvme-$attr{wwid}-part%n"'
    echo 'KERNEL=="nvme*[0-9]n*[0-9]", ENV{DEVTYPE}=="disk", ATTRS{serial}=="?*", ENV{ID_SERIAL_SHORT}="$attr{serial}"'
    echo 'KERNEL=="nvme*[0-9]n*[0-9]", ENV{DEVTYPE}=="disk", ATTRS{wwid}=="?*", ENV{ID_WWN}="$attr{wwid}"'
    echo 'KERNEL=="nvme*[0-9]n*[0-9]", ENV{DEVTYPE}=="disk", ATTRS{model}=="?*", ENV{ID_MODEL}="$attr{model}"'
    echo 'KERNEL=="nvme*[0-9]n*[0-9]", ENV{DEVTYPE}=="disk", ENV{ID_MODEL}=="?*", ENV{ID_SERIAL_SHORT}=="?*", \'
    echo '  ENV{ID_SERIAL}="$env{ID_MODEL}_$env{ID_SERIAL_SHORT}", SYMLINK+="disk/by-id/nvme-$env{ID_SERIAL}"'
    echo 'KERNEL=="nvme*[0-9]n*[0-9]p*[0-9]", ENV{DEVTYPE}=="partition", ATTRS{serial}=="?*", ENV{ID_SERIAL_SHORT}="$attr{serial}"'
    echo 'KERNEL=="nvme*[0-9]n*[0-9]p*[0-9]", ENV{DEVTYPE}=="partition", ATTRS{model}=="?*", ENV{ID_MODEL}="$attr{model}"'
    echo 'KERNEL=="nvme*[0-9]n*[0-9]p*[0-9]", ENV{DEVTYPE}=="partition", ENV{ID_MODEL}=="?*", ENV{ID_SERIAL_SHORT}=="?*", \'
    echo '  ENV{ID_SERIAL}="$env{ID_MODEL}_$env{ID_SERIAL_SHORT}", SYMLINK+="disk/by-id/nvme-$env{ID_SERIAL}-part%n"'
  } > /etc/udev/rules.d/99-installimage.rules
  udevadm control -R && udevadm trigger && udevadm settle
  local paths; paths=()
  while read drive; do
    paths+=("$(drive_disk_by_id_path "$drive")")
  done < <(grub_install_devices)
  local value; value=''
  for path in "${paths[@]}"; do
    [[ -z "$path" ]] && return 1
    value+="$path, "
  done
  debconf_set "grub-pc grub-pc/install_devices multiselect ${value::-2}"
}
