#!/bin/bash
#
# RHEL specific functions
#
# (c) 2008-2021, Hetzner Online GmbH
#

# generate_config_mdadm "NIL"
generate_config_mdadm() {
  [[ -z "$1" ]] && return 0

  local mdadmconf='/etc/mdadm.conf'
  {
    echo 'DEVICE partitions'
    echo 'MAILADDR root'
  } > "${FOLD}/hdd${mdadmconf}"

  execute_chroot_command "mdadm --examine --scan >> ${mdadmconf}"
  return $?
}

# generate_new_ramdisk "NIL"
generate_new_ramdisk() {
  [[ -z "$1" ]] && return 0

  blacklist_unwanted_and_buggy_kernel_modules
  configure_kernel_modules

  local dracutfile="${FOLD}/hdd/etc/dracut.conf.d/99-${C_SHORT}.conf"
  cat << EOF > "$dracutfile"
### ${COMPANY} - installimage
add_dracutmodules+=" lvm mdraid "
add_drivers+=" raid0 raid1 raid10 raid456 "
hostonly="no"
hostonly_cmdline="no"
lvmconf="yes"
mdadmconf="yes"
persistent_policy="by-uuid"
EOF

  # generate initramfs for the latest kernel
  execute_chroot_command "dracut -f --kver $(find "${FOLD}/hdd/boot/" -name 'vmlinuz-*' | cut -d '-' -f 2- | sort -V | tail -1)"
  return $?
}

#
# generate_config_grub <version>
#
# Generate the GRUB bootloader configuration.
#
generate_config_grub() {
  local grubdefconf="${FOLD}/hdd/etc/default/grub"
  local exitcode
  local grub_cmdline_linux='biosdevname=0 rd.auto=1 consoleblank=0'

  # rebuild device map
  rm -f "${FOLD}/hdd/boot/grub2/device.map"
  build_device_map 'grub2'

  if [[ "$IMG_VERSION" -gt 93 ]] && [[ "$IMG_VERSION" -lt 810 ]]; then
    grub_cmdline_linux+=' crashkernel=1G-4G:192M,4G-64G:256M,64G-:512M'
  else
    grub_cmdline_linux+=' crashkernel=auto'
  fi

  # nomodeset can help avoid issues with some GPUs.
  if ((USE_KERNEL_MODE_SETTING == 0)); then
    grub_cmdline_linux+=' nomodeset'
  fi

  # 'noop' scheduler is used in VMs to reduce overhead.
  if is_virtual_machine; then
    grub_cmdline_linux+=' elevator=noop'
  fi

  # disable memory-mapped PCI configuration
  if has_threadripper_cpu; then
    grub_cmdline_linux+=' pci=nommconf'
  fi

  if [[ "$SYSARCH" == "arm64" ]]; then
    grub_cmdline_linux+=' console=ttyAMA0 console=tty0'
  fi

  sed -i "s/GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"${grub_cmdline_linux}\"/" "$grubdefconf"

  # set $GRUB_DEFAULT_OVERRIDE to specify custom GRUB_DEFAULT Value ( https://www.gnu.org/software/grub/manual/grub/grub.html#Simple-configuration )
  [[ -n "$GRUB_DEFAULT_OVERRIDE" ]] && sed -i "s/^GRUB_DEFAULT=.*/GRUB_DEFAULT=${GRUB_DEFAULT_OVERRIDE}/" "$grubdefconf"

  # Generate grub.cfg
  if [[ "$IMG_VERSION" -gt 93 ]] && [[ "$IMG_VERSION" -lt 810 ]]; then
    # https://docs.rockylinux.org/en/latest/reference/grub2/grub2-mkconfig/
    execute_chroot_command 'grub2-mkconfig -o /boot/grub2/grub.cfg --update-bls-cmdline 2>&1'
  else
    execute_chroot_command 'grub2-mkconfig -o /boot/grub2/grub.cfg 2>&1'
  fi
  exitcode=$?

  grub2_uuid_bugfix 'rhel'
  return "$exitcode"
}

write_grub() {
  local exitcode
  if [[ "$UEFI" -eq 1 ]]; then
    execute_chroot_command "grub2-install --target=${SYSARCH}-efi --efi-directory=/boot/efi/ --bootloader-id=${IAM} --force --removable --no-nvram 2>&1"
    exitcode=$?
  else
    # Only install grub2 in MBR of all other drives if we use SWRAID
    for ((i = 1; i <= COUNT_DRIVES; i++)); do
      if [[ "$SWRAID" -eq 1 || "$i" -eq 1 ]]; then
        execute_chroot_command "grub2-install --no-floppy --recheck $(eval echo "\$DRIVE${i}") 2>&1"
        exitcode=$?
      fi
    done
  fi
  return "$exitcode"
}

#
# os specific functions
# for purpose of e.g. debian-sys-maint mysql user password in debian/ubuntu LAMP
#
run_os_specific_functions() {
  randomize_mdadm_array_check_time

  if [[ "$IMG_VERSION" -lt 90 ]]; then
    execute_chroot_command 'chkconfig iptables off'
    execute_chroot_command 'chkconfig ip6tables off'
    is_plesk_install || execute_chroot_command 'chkconfig postfix off'
  fi

  #
  # setup env in cpanel image
  #
  debug '# Testing and setup of cpanel image'
  if [[ -f "${FOLD}/hdd/etc/wwwacct.conf" && -f "${FOLD}/hdd/etc/cpupdate.conf" ]]; then
    grep -q -i cpanel <<< "$IMAGE_FILE" && {
      setup_cpanel || return 1
    }
  fi

  # selinux autorelabel if enabled
  grep -Eq 'SELINUX=(enforcing|permissive)' "${FOLD}/hdd/etc/sysconfig/selinux" &&
    touch "${FOLD}/hdd/.autorelabel"

   mkdir -p "${FOLD}/hdd/var/run/netreport"

  return 0
}

# vim: ai:ts=2:sw=2:et
