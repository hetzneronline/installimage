#!/usr/bin/env bash

#
# archlinux functions
#
# (c) 2013-2021, Hetzner Online GmbH
#

validate_image() {
  [[ -e "$ARCHLINUX_RELEASE_KEY" ]] || return 3
  debug "# importing archlinux release key $(readlink -f "$ARCHLINUX_RELEASE_KEY")"
  gpg --batch --import "$ARCHLINUX_RELEASE_KEY" |& debugoutput
  local sig_file="$ARCHLINUX_BOOTSTRAP.sig"
  [[ -e "$sig_file" ]] || return 2
  debug "# verifying archlinux bootstrap $(readlink -f "$ARCHLINUX_BOOTSTRAP") using sig file $(readlink -f "$sig_file")"
  gpg --batch --verify "$sig_file" "$ARCHLINUX_BOOTSTRAP" |& debugoutput
}

extract_image() {
  # only extract images with content, pacstrap otherwise
  if [[ -s "$EXTRACTFROM" ]]; then
    (source "$FUNCTIONSFILE"; extract_image "$@")
    return $?
  fi

  debug '# empty image provided. run pacstrap install'

  # symlink to latest archlinux-bootstrap
  local archlinux_mirror='https://mirror.hetzner.com/archlinux'
  local archlinux_packages='base btrfs-progs cronie cryptsetup gptfdisk grub haveged linux linux-firmware lvm2 mdadm net-tools openssh python rsync vim wget xfsprogs inetutils'

  # dont extract archlinux-bootstrap to system memory but the target disk
  local hdd_dir="$FOLD/hdd"
  debug '# extract archlinux-bootstrap to disk'
  debug "# run tar xzf $ARCHLINUX_BOOTSTRAP -C $hdd_dir"
  tar --zstd -xf "$ARCHLINUX_BOOTSTRAP" -C "$hdd_dir" |& debugoutput || return 1

  # pacman CheckSpace requires a mount to verify free space
  local chroot_dir="$hdd_dir/root.x86_64"
  debug '# bindmount bootstrap dir for pacman CheckSpace'
  debug "# mount --bind $chroot_dir $chroot_dir"
  mount --bind "$chroot_dir" "$chroot_dir" |& debugoutput || return 1

  # init pacman
  debug '# archlinux-bootstrap: init pacman'
  local arch_chroot_script="$chroot_dir/usr/bin/arch-chroot"
  for opt in --init '--populate archlinux'; do
    debug "# archlinux-bootstrap: run $arch_chroot_script $chroot_dir pacman-key $opt"
    "$arch_chroot_script" "$chroot_dir" pacman-key $opt |& debugoutput || return 1
  done
  local mirrorlist="$chroot_dir/etc/pacman.d/mirrorlist"
  debug "# archlinux-bootstrap: add hetzner mirror to /etc/pacman.d/mirrorlist"
  echo "Server=$archlinux_mirror/\$repo/os/\$arch" > "$mirrorlist" || return 1
  for opt in -Syy '--noconfirm -S archlinux-keyring'; do
    debug "# archlinux-bootstrap: run $arch_chroot_script $chroot_dir pacman $opt"
    "$arch_chroot_script" "$chroot_dir" pacman $opt |& debugoutput || return 1
  done

  # pacstrap
  local newroot='/mnt'
  debug "# archlinux-bootstrap: run $arch_chroot_script $chroot_dir pacstrap -G -M $newroot $archlinux_packages"
  "$arch_chroot_script" "$chroot_dir" pacstrap -G -M "$newroot" $archlinux_packages |& debugoutput || return 1

  # move newroot
  debug '# move /mnt to /'
  umount "$chroot_dir" |& debugoutput || return 1
  debug "# run rsync -a --remove-source-files $chroot_dir/$newroot/ $hdd_dir/"
  rsync -a --remove-source-files "$chroot_dir/$newroot/" "$hdd_dir/" |& debugoutput || return 1

  # wait_for_udev before generating fstab
  wait_for_udev

  # genfstab
  debug '# setup /etc/fstab'
  local fstab="$hdd_dir/etc/fstab"
  local fstab_bak="$fstab.bak"
  cp "$fstab" "$fstab_bak"
  # fstab convert dev to disk by uuid paths
  {
    while read line; do
      if [[ "$line" =~ ^[\ ]*(/dev/[^\ ]+) ]]; then
        i=0
        for l in /dev/disk/by-uuid/*; do
          [[ "$(readlink -f "$l")" == "$(readlink -f "${BASH_REMATCH[1]}")" ]] || continue
          sed "s\\${BASH_REMATCH[1]}\\UUID=${l##*/}\\g" <<< "$line"
          i=1
          break
        done
        ((i == 1)) || echo "$line"
        continue
      fi
      echo "$line"
    done < "$FOLD/fstab"
  } >> "$fstab"
  diff -Naur "$fstab_bak" "$fstab" | debugoutput

  # remove archlinux-bootstrap
  debug '# remove archlinux-bootstrap'
  rm -fr "$chroot_dir" |& debugoutput || return 1

  # setup locale
  debug "# setup /etc/locale.gen"
  local locale_gen_file="$hdd_dir/etc/locale.gen"
  local locale_gen_file_bak="$locale_gen_file.bak"
  cp "$locale_gen_file" "$locale_gen_file_bak"
  sed -i 's/#en_US\.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' "$locale_gen_file" |& debugoutput || return 1
  diff -Naur "$locale_gen_file_bak" "$locale_gen_file" | debugoutput
  execute_chroot_command locale-gen || return 1
  debug "# create /etc/locale.conf"
  local locale_conf="$hdd_dir/etc/locale.conf"
  echo 'LANG=en_US.UTF-8' > "$locale_conf" || return 1
  diff -Naur /dev/null "$locale_conf" | debugoutput

  # setup bash_profile
  local bash_profile_file="$hdd_dir/root/.bash_profile"
  # do not overwrite, fail if bash_profile exists
  [[ -e "$bash_profile_file" ]] && return 1
  debug "# create /root/.bash_profile"
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
  diff -Naur /dev/null "$bash_profile_file" | debugoutput

  # setup localtime
  local localtime_file="$hdd_dir/etc/localtime"
  debug "# point /etc/localtime to /usr/share/zoneinfo/Europe/Berlin"
  ln -f -s /usr/share/zoneinfo/Europe/Berlin "$localtime_file" |& debugoutput || return 1
  ls -la "$localtime_file" | debugoutput

  # setup mirrorlist
  debug '# enable all mirrors in /etc/pacman.d/mirrorlist'
  local mirrorlist="$hdd_dir/etc/pacman.d/mirrorlist"
  sed -i s/^#Server/Server/g "$mirrorlist"
  debug "# add hetzner mirror to /etc/pacman.d/mirrorlist"
  local mirrorlist_bak="$mirrorlist.bak"
  cp "$mirrorlist" "$mirrorlist_bak" |& debugoutput || return 1
  {
    echo "### $COMPANY installimage"
    echo
    echo "## $COMPANY"
    echo "Server=$archlinux_mirror/\$repo/os/\$arch"
    echo
    cat "$mirrorlist_bak"
  } > "$mirrorlist" || return 1
  diff -Naur "$mirrorlist_bak" "$mirrorlist" | debugoutput

  # setup resolv.conf
  local resolv_conf="$hdd_dir/etc/resolv.conf"
  debug "# create /etc/resolv.conf"
  {
    echo "### $COMPANY installimage"
    echo '# nameserver config'
    while read nsaddr; do
      echo "nameserver $nsaddr"
    done < <(randomized_nsaddrs)
  } > "$resolv_conf" || return 1
  diff -Naur /dev/null "$resolv_conf" | debugoutput

  # setup vconsole.conf
  debug "# create /etc/vconsole.conf"
  local vconsole_conf="$hdd_dir/etc/vconsole.conf"
  echo 'KEYMAP=de-latin1-nodeadkeys' > "$vconsole_conf" || return 1
  diff -Naur /dev/null "$vconsole_conf" | debugoutput

  # init pacman
  debug '# init pacman'
  execute_chroot_command 'pacman-key --init' || return 1
  execute_chroot_command "pacman-key --populate archlinux" || return 1

  # enable services
  debug '# enable services'
  for opt in cronie haveged sshd systemd-timesyncd; do
    systemd_nspawn "systemctl enable $opt" || return 1
  done

  # sshdgenkeys.service will generate keys on first boot but we need them now
  if [[ ! -e "$hdd_dir/etc/ssh/ssh_host_dsa_key" ]] || \
    [[ ! -e "$hdd_dir/etc/ssh/ssh_host_dsa_key.pub" ]] || \
    [[ ! -e "$hdd_dir/etc/ssh/ssh_host_ecdsa_key" ]] || \
    [[ ! -e "$hdd_dir/etc/ssh/ssh_host_ecdsa_key.pub" ]] || \
    [[ ! -e "$hdd_dir/etc/ssh/ssh_host_ed25519_key" ]] || \
    [[ ! -e "$hdd_dir/etc/ssh/ssh_host_ed25519_key.pub" ]] || \
    [[ ! -e "$hdd_dir/etc/ssh/ssh_host_rsa_key" ]] || \
    [[ ! -e "$hdd_dir/etc/ssh/ssh_host_rsa_key.pub" ]]; then
    debug 'No ssh host keys found, generating host keys'
    execute_chroot_command 'ssh-keygen -A'
  fi
}

generate_config_mdadm() {
  [[ -z "$1" ]] && return
  debug "# setup /etc/mdadm.conf"
  local hdd_dir="$FOLD/hdd"
  local mdadm_conf='/etc/mdadm.conf'
  local mdadm_conf_bak="$hdd_dir/$mdadm_conf.bak"
  cp "$hdd_dir/$mdadm_conf" "$mdadm_conf_bak"
  sed -i 's/^#MAILADDR root@mydomain.tld$/MAILADDR root/g' "$hdd_dir/$mdadm_conf" |& debugoutput || return 1
  echo >> "$hdd_dir/$mdadm_conf" || return 1
  execute_chroot_command "mdadm --examine --scan >> $mdadm_conf"
  diff -Naur "$mdadm_conf_bak" "$hdd_dir/$mdadm_conf" | debugoutput || :
}

generate_new_ramdisk() {
  [[ -z "$1" ]] && return
  local hdd_dir="$FOLD/hdd"
  blacklist_unwanted_and_buggy_kernel_modules
  configure_kernel_modules
  debug "# setup /etc/mkinitcpio.conf"
  local mkinitcpio_conf="$hdd_dir/etc/mkinitcpio.conf"
  local mkinitcpio_conf_bak="$mkinitcpio_conf.bak"
  cp "$mkinitcpio_conf" "$mkinitcpio_conf_bak"
  local hooks=()
  for hook in $(source "$mkinitcpio_conf"; echo "${HOOKS[@]}"); do
    hooks+=("$hook")
    [[ "$hook" != 'block' ]] && continue
    hooks+=('mdadm_udev' 'lvm2')
    if [ "$CRYPT" = "1" ]; then
      hooks+=('encrypt')
    fi
  done
  sed -i "s/^HOOKS=.*/HOOKS=(${hooks[*]})/" "$mkinitcpio_conf" |& debugoutput || return 1
  diff -Naur "$mkinitcpio_conf_bak" "$mkinitcpio_conf" | debugoutput
  execute_chroot_command 'mkinitcpio -p linux'
}

generate_config_grub() {
  debug "# setup /etc/default/grub"
  local grub_file="$FOLD/hdd/etc/default/grub"
  local grub_file_bak="$grub_file.bak"
  cp "$grub_file" "$grub_file_bak"
  local grub_linux_default="consoleblank=0"
  (( USE_KERNEL_MODE_SETTING == 0 )) && grub_linux_default+=' nomodeset'
  has_threadripper_cpu && grub_linux_default+=' pci=nommconf'
  sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"${grub_linux_default}\"/g" "$grub_file" |& debugoutput || return 1
  diff -Naur "$grub_file_bak" "$grub_file" | debugoutput

  debug '# install grub'
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
  randomize_mdadm_array_check_time
}

# vim: ai:ts=2:sw=2:et
