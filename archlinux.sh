#!/usr/bin/env bash

#
# archlinux functions
#
# (c) 2013-2018, Hetzner Online GmbH
#

validate_image() { return 2; }

extract_image() {
  if [[ -s "$EXTRACTFROM" ]]; then
    $(source "$FUNCTIONSFILE"; extract_image "$@")
    return $?
  fi

  local archlinux_bootstrap_archive="$SCRIPTPATH/../archlinux/archlinux-bootstrap-latest-x86_64.tar.gz"
  local hdd_dir="$FOLD/hdd"

  debug "# run tar xzf $archlinux_bootstrap_archive -C $hdd_dir"
  tar xzf "$archlinux_bootstrap_archive" -C "$hdd_dir" |& debugoutput || return 1

  local chroot_dir="$hdd_dir/root.x86_64"
  debug "# mount --bind $chroot_dir $chroot_dir"
  mount --bind "$chroot_dir" "$chroot_dir" |& debugoutput || return 1
  local arch_chroot_script="$chroot_dir/usr/bin/arch-chroot"
  "$arch_chroot_script" "$chroot_dir" pacman-key --init |& debugoutput || return 1
  # without v6 connectivity --refresh-keys fails
  echo 'disable-ipv6' > "$chroot_dir/etc/pacman.d/gnupg/dirmngr.conf"
  # $ dig hkps.pool.sks-keyservers.net | grep status
  # ;; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN, id: 17975
  local keyserver='pool.sks-keyservers.net'
  for opt in '--populate archlinux' "--refresh-keys --keyserver=$keyserver"; do
    debug "# run $arch_chroot_script $chroot_dir pacman-key $opt"
    "$arch_chroot_script" "$chroot_dir" pacman-key $opt |& debugoutput || return 1
  done

  local mirrorlist="$chroot_dir/etc/pacman.d/mirrorlist"
  local archlinux_mirror_uri='https://mirror.hetzner.de/archlinux'
  debug "# update $mirrorlist"
  echo "Server=$archlinux_mirror_uri/\$repo/os/\$arch" > "$mirrorlist" || return 1
  for opt in -Syy '--noconfirm -S archlinux-keyring'; do
    debug "# run $arch_chroot_script $chroot_dir pacman $opt"
    "$arch_chroot_script" "$chroot_dir" pacman $opt |& debugoutput || return 1
  done

  local newroot_dir='/mnt'
  local archlinux_packages='base btrfs-progs cronie gptfdisk grub haveged net-tools openssh rsync vim wget python linux mdadm lvm2 xfsprogs'
  debug "# run $arch_chroot_script $chroot_dir pacstrap -d -G -M $newroot_dir $archlinux_packages"
  "$arch_chroot_script" "$chroot_dir" pacstrap -d -G -M "$newroot_dir" $archlinux_packages |& debugoutput || return 1
  debug "# umount $chroot_dir"
  umount "$chroot_dir" |& debugoutput || return 1
  debug "# run rsync -a --remove-source-files $chroot_dir/$newroot_dir/ $hdd_dir/"
  rsync -a --remove-source-files "$chroot_dir/$newroot_dir/" "$hdd_dir/" |& debugoutput || return 1

  local fstab="$hdd_dir/etc/fstab"
  debug "# update $fstab"
  {
    echo
    # "$chroot_dir/usr/bin/genfstab" -U "$hdd_dir"
    cat "$FOLD/fstab"
  } >> "$fstab" || return 1
  debug "# run rm -fr $chroot_dir"
  rm -fr "$chroot_dir" |& debugoutput || return 1

  local locale_gen_file="$hdd_dir/etc/locale.gen"
  debug "# update $locale_gen_file"
  sed -i 's/#en_US\.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' "$locale_gen_file" |& debugoutput || return 1
  execute_chroot_command locale-gen || return 1

  local locale_conf="$hdd_dir/etc/locale.conf"
  debug "# create $locale_conf"
  echo 'LANG=en_US.UTF-8' > "$locale_conf" || return 1

  local bash_profile_file="$hdd_dir/root/.bash_profile"
  debug "# create $bash_profile_file"
  {
    echo "### $COMPANY installimage"
    echo
    echo "alias ls='ls --color=auto'"
    echo "alias ll='ls -l'"
    echo "alias l='ls -A'"
    echo 'HISTCONTROL=ignoreboth'
    echo 'HISTFILESIZE=-1'
    echo 'HISTSIZE=-1'
  } > "$bash_profile_file" || return 1

  local inputrc="$hdd_dir/etc/inputrc"
  debug "# update $inputrc"
  sed -i 's/"\\\e\[5~": beginning-of-history/#"\e[5~": beginning-of-history\n"\e[5~": history-search-backward/' "$inputrc" |& debugoutput || return 1
  sed -i 's/"\\\e\[6~": end-of-history/#"\e[6~": end-of-history\n"\e[6~": history-search-forward/' "$inputrc" |& debugoutput || return 1

  local localtime_file="$hdd_dir/etc/localtime"
  debug "# link $localtime_file"
  ln -f -s /usr/share/zoneinfo/Europe/Berlin "$localtime_file" |& debugoutput || return 1

  local mirrorlist="$hdd_dir/etc/pacman.d/mirrorlist"
  local mirrorlist_bak="$mirrorlist.bak"
  debug "# update $mirrorlist"
  mv "$mirrorlist" "$mirrorlist_bak" |& debugoutput || return 1
  {
    echo "### $COMPANY installimage"
    echo
    echo "## $COMPANY"
    echo "Server=$archlinux_mirror_uri/\$repo/os/\$arch"
    echo
    sed s/^#Server/Server/g "$mirrorlist_bak"
  } > "$mirrorlist" || return 1

  local resolv_conf="$hdd_dir/etc/resolv.conf"
  debug "# update $resolv_conf"
  {
    for ip in $(shuf -e "${NAMESERVER[@]}") $(shuf -e "${DNSRESOLVER_V6[@]}"); do
      echo "nameserver $ip"
    done
  } > "$resolv_conf" || return 1

  local vconsole_conf="$hdd_dir/etc/vconsole.conf"
  debug "# create $vconsole_conf"
  echo 'KEYMAP=de-latin1-nodeadkeys' > "$vconsole_conf" || return 1
  execute_chroot_command 'pacman-key --init'
  # without v6 connectivity --refresh-keys fails
  echo 'disable-ipv6' > "$hdd_dir/etc/pacman.d/gnupg/dirmngr.conf"
  for opt in '--populate archlinux' "--refresh-keys --keyserver=$keyserver"; do
    execute_chroot_command "pacman-key $opt" || return 1
  done
  rm "$hdd_dir/etc/pacman.d/gnupg/dirmngr.conf" || return 1
  for opt in cronie haveged systemd-timesyncd; do
    execute_chroot_command "systemctl enable $opt" || return 1
  done
}

generate_config_mdadm() {
  [[ -z "$1" ]] && return
  local hdd_dir="$FOLD/hdd"
  local mdadm_conf='/etc/mdadm.conf'
  debug "# update $hdd_dir/$mdadm_conf"
  sed -i 's/^#MAILADDR root@mydomain.tld$/MAILADDR root/g' "$hdd_dir/$mdadm_conf" |& debugoutput || return 1
  echo >> "$hdd_dir/$mdadm_conf" || return 1
  execute_chroot_command "mdadm --examine --scan >> $mdadm_conf"
}

generate_new_ramdisk() {
  [[ -z "$1" ]] && return
  local hdd_dir="$FOLD/hdd"
  local blacklist_conf="$hdd_dir/etc/modprobe.d/blacklist.conf"
  debug "# create $blacklist_conf"
  {
    echo "### $COMPANY installimage"
    echo
    for module in i915 mei mei-me pcspkr snd_pcsp sm750fb; do
      echo "blacklist $module"
    done
  } > "$blacklist_conf" || return 1
  local mkinitcpio_conf="$hdd_dir/etc/mkinitcpio.conf"
  debug "# update $mkinitcpio_conf"
  local hooks=()
  for hook in $(source "$mkinitcpio_conf"; echo "${HOOKS[@]}"); do
    hooks+=("$hook")
    [[ "$hook" != 'block' ]] && continue
    hooks+=('mdadm_udev' 'lvm2')
  done
  sed -i "s/^HOOKS=.*/HOOKS=(${hooks[*]})/" "$mkinitcpio_conf" |& debugoutput || return 1
  execute_chroot_command 'mkinitcpio -p linux'
}

setup_cpufreq() { return; }

generate_config_grub() {
  local grub_file="$FOLD/hdd/etc/default/grub"
  debug "# update $grub_file"
  local grub_linux_default="consoleblank=0 nomodeset"

  if has_threadripper_cpu; then
    grub_linux_default+=' pci=nommconf'
  fi

  if is_dell_r6415; then
    grub_linux_default=${grub_linux_default/nomodeset }
  fi

  sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"${grub_linux_default}\"/g" "$grub_file" |& debugoutput || return 1
  if [ "$UEFI" -eq 1 ]; then
    local efi_target="x86_64-efi"
    local efi_dir="/boot/efi"
    local efi_grub_options="--no-floppy --no-nvram --removable"
    execute_chroot_command "grub-install --target=${efi_target} --efi-directory=${efi_dir} ${efi_grub_options} 2>&1"
    execute_chroot_command "umount /run; grub-mkconfig -o /boot/grub/grub.cfg; mount --bind /var/empty /run" || return 1
  else
    execute_chroot_command "grub-install $DRIVE1" || return 1
    # If /run is mounted, grub-mkconfig will gen broken configs
    # execute_chroot_command "grub-mkconfig -o /boot/grub/grub.cfg" || return 1
    execute_chroot_command "umount /run; grub-mkconfig -o /boot/grub/grub.cfg; mount --bind /var/empty /run" || return 1
    execute_chroot_command "grub-install $DRIVE1" || return 1
    [[ "$SWRAID" != 1 ]] && return
    local i=2
    while :; do
      local drive="$(eval echo "\$DRIVE$i")"
      [[ -n "$drive" ]] || break
      execute_chroot_command "grub-install $drive" || return 1
      ((i++))
    done
  fi
}

run_os_specific_functions() {
  execute_chroot_command 'systemctl enable sshd'
}

# vim: ai:ts=2:sw=2:et
