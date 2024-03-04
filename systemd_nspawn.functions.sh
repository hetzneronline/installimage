#!/usr/bin/env bash

#
# systemd_nspawn functions
#
# (c) 2015-2024, Hetzner Online GmbH
#

# protect files from systemd
polite_nspawn() {
  local ubuntu_gte_1804_args
  if [[ "$IAM" == 'ubuntu' ]] && (( IMG_VERSION >= 1804 )); then
    cp /etc/resolv.conf "$FOLD/nspawn_stub_resolv.conf"
    ubuntu_gte_1804_args+="--bind=$(printf '%q' "$FOLD/nspawn_stub_resolv.conf"):/run/systemd/resolve/stub-resolv.conf"
  fi

  # no manual protection needed for systemd >= 239
  if (( $(rescue_systemd_version) >= 239 )); then
    # off means leave as is
    systemd-nspawn $ubuntu_gte_1804_args --resolv-conf=off "$@"
    return $?
  fi

  local lt_239_args='--bind-ro=/etc/resolv.conf:/run/resolvconf/resolv.conf'
  lt_239_args+=' --bind-ro=/etc/resolv.conf:/run/systemd/resolve/stub-resolv.conf'

  if ! [[ -L "$FOLD/hdd/etc/resolv.conf" ]] && ! [[ -e "$FOLD/hdd/etc/resolv.conf" ]]; then
    systemd-nspawn $ubuntu_gte_1804_args $lt_239_args "$@"
    return $?
  fi

  # prepare nspawn_resolv.conf
  if [[ -L "$FOLD/hdd/etc/resolv.conf" ]] && ! [[ -e "$FOLD/hdd/etc/resolv.conf" ]]; then
    cp /etc/resolv.conf "$FOLD/nspawn_resolv.conf"
  else
    cp "$FOLD/hdd/etc/resolv.conf" "$FOLD/nspawn_resolv.conf"
  fi

  # choose protection strategy
  if [[ -L "$FOLD/hdd/etc/resolv.conf" ]]; then
    mv "$FOLD/hdd/etc/resolv.conf" "$FOLD/resolv.bak"
    cp "$FOLD/nspawn_resolv.conf" "$FOLD/hdd/etc/resolv.conf"
  else
    mount --bind "$FOLD/nspawn_resolv.conf" "$FOLD/hdd/etc/resolv.conf"
  fi

  systemd-nspawn $ubuntu_gte_1804_args $lt_239_args "$@"

  # restore
  if [[ -L "$FOLD/resolv.bak" ]]; then
    rm "$FOLD/hdd/etc/resolv.conf"
    mv "$FOLD/resolv.bak" "$FOLD/hdd/etc/resolv.conf"
  else
    umount "$FOLD/hdd/etc/resolv.conf"
  fi
}

# systemd_nspawn_booted() { [[ -e "$FOLD/.#hdd.lck" ]]; }
systemd_nspawn_booted() { pkill -0 systemd-nspawn; }

boot_systemd_nspawn() {
  [[ -d "$SYSTEMD_NSPAWN_TMP_DIR" ]] && rm -fr "$SYSTEMD_NSPAWN_TMP_DIR"
  mkdir -p "$SYSTEMD_NSPAWN_TMP_DIR"
  for fifo in {command,in,out,return}.fifo; do
    mkfifo "$SYSTEMD_NSPAWN_TMP_DIR/$fifo"
  done
  {
    echo '#!/usr/bin/env bash'
    echo 'while :; do'
    # shellcheck disable=SC2016
    echo '  command="$(cat /var/lib/systemd_nspawn/command.fifo)"'
    # shellcheck disable=SC2016
    echo '  cat /var/lib/systemd_nspawn/in.fifo | HOME=/root /usr/bin/env bash -c "$command" &> /var/lib/systemd_nspawn/out.fifo'
    echo '  echo $? > /var/lib/systemd_nspawn/return.fifo'
    echo 'done &'
  } > "$SYSTEMD_NSPAWN_TMP_DIR/runner"
  chmod +x "$SYSTEMD_NSPAWN_TMP_DIR/runner"
  {
    echo '[Unit]'
    echo '[Service]'
    echo 'ExecStart=/usr/local/bin/systemd_nspawn-runner'
    echo 'KillMode=none'
    echo 'Type=forking'
  } > "$SYSTEMD_NSPAWN_TMP_DIR/systemd_nspawn-runner.service"
  ln -s ../systemd_nspawn-runner.service "$FOLD/hdd/etc/systemd/system/multi-user.target.wants"

  polite_nspawn -b \
    --bind-ro="$SYSTEMD_NSPAWN_TMP_DIR/command.fifo:/var/lib/systemd_nspawn/command.fifo" \
    --bind-ro="$SYSTEMD_NSPAWN_TMP_DIR/in.fifo:/var/lib/systemd_nspawn/in.fifo" \
    --bind-ro="$SYSTEMD_NSPAWN_TMP_DIR/out.fifo:/var/lib/systemd_nspawn/out.fifo" \
    --bind-ro="$SYSTEMD_NSPAWN_TMP_DIR/return.fifo:/var/lib/systemd_nspawn/return.fifo" \
    --bind-ro="$SYSTEMD_NSPAWN_TMP_DIR/runner:/usr/local/bin/systemd_nspawn-runner" \
    --bind-ro="$SYSTEMD_NSPAWN_TMP_DIR/systemd_nspawn-runner.service:/etc/systemd/system/systemd_nspawn-runner.service" \
    -D "$FOLD/hdd" \
    -M newroot &> /dev/null &

  until systemd_nspawn_booted; do sleep 1; done

  # systemd-nspawn may overlay our runner service
  if ! [[ -e "$FOLD/hdd/etc/systemd/system/multi-user.target.wants/systemd_nspawn-runner.service" ]]; then
    # relink and reboot
    ln -s ../systemd_nspawn-runner.service "$FOLD/hdd/etc/systemd/system/multi-user.target.wants"
    machinectl reboot newroot
  fi

  until systemd_nspawn_wo_debug : &> /dev/null; do
    sleep 1;
  done
}

systemd_nspawn_wo_debug() {
  if ! systemd_nspawn_booted; then
    # only bind mount block devices
    local dev_bind_args=()
    while read f; do
      stat "$f" &> /dev/null || continue
      f="$(echo "$f" | sed s/:/\\\\:/g)"
      dev_bind_args+=("--bind=$f")
    done < <(find /dev -xtype b)

    # systemd > 241 added and requires --pipe to not use Windows line breaks 🤡
    local gt_241_args=''
    (( $(rescue_systemd_version) > 241 )) && gt_241_args='--pipe'

    polite_nspawn "${dev_bind_args[@]}" \
      -D "$FOLD/hdd" \
      '--property=DeviceAllow=block-* rwm' \
      '--property=DeviceAllow=/dev/mapper/control rwm' \
      -q $gt_241_args /usr/bin/env bash -c "$*"
    r=$?
    return $r
  fi
  echo "$@" > "$SYSTEMD_NSPAWN_TMP_DIR/command.fifo"
  if [[ -t 0 ]]; then
    echo -n > "$SYSTEMD_NSPAWN_TMP_DIR/in.fifo"
  else
    cat > "$SYSTEMD_NSPAWN_TMP_DIR/in.fifo"
  fi
  cat "$SYSTEMD_NSPAWN_TMP_DIR/out.fifo"
  return "$(timeout -s 9 120 cat "$SYSTEMD_NSPAWN_TMP_DIR/return.fifo")"
}

systemd_nspawn() {
  debug "# systemd_nspawn: $*"
  systemd_nspawn_wo_debug "$@" |& debugoutput
  return "${PIPESTATUS[0]}"
}

poweroff_systemd_nspawn() {
  systemd_nspawn_wo_debug 'systemctl --force poweroff &> /dev/null &'
  while systemd_nspawn_booted; do sleep 1; done
  rm -fr "$FOLD/hdd/"{var/lib/systemd_nspawn,usr/local/bin/systemd_nspawn-runner,etc/systemd/system/systemd_nspawn-runner.service}
  unlink "$FOLD/hdd/etc/systemd/system/multi-user.target.wants/systemd_nspawn-runner.service"
}

verify_machinectl_login_works() {
  local password="$1"

  debug '# verify machinectl login works'

  local securetty_file="$FOLD/hdd/etc/securetty"
  if [[ -e "$securetty_file" ]]; then
    local tmp_securetty="$FOLD/tmp_securetty"

    debug 'adjusting /etc/securetty to allow login from /dev/pts/*'

    cp "$securetty_file" "$tmp_securetty"
    for i in {0..255}; do echo "pts/$i" >> "$tmp_securetty"; done
    mount --bind "$tmp_securetty" "$securetty_file"
  fi

  boot_systemd_nspawn || return 1

  local session="$$.tmp_installimage_test_machinectl_login"
  screen -d -m -S "$session" machinectl login newroot

  until last_nonempty_line_of_screen_output_matches "$session" ' login:$'; do sleep 1; done
  screen -S "$session" -X stuff "root^M"
  while last_nonempty_line_of_screen_output_matches "$session" ' login: root$'; do sleep 1; done
  if ! last_nonempty_line_of_screen_output_matches "$session" '^Password:$'; then
    debug 'login failed. did not get a password prompt:'
    get_screen_output "$session" | debugoutput

    poweroff_systemd_nspawn
    [[ -e "$securetty_file" ]] && umount "$securetty_file"
    return 1
  fi

  until last_nonempty_line_of_screen_output_matches "$session" '^Password:$'; do sleep 1; done
  screen -S "$session" -X stuff "$password^M"
  while last_nonempty_line_of_screen_output_matches "$session" '^Password:$'; do sleep 1; done
  if last_nonempty_line_of_screen_output_matches "$session" ' login:$'; then
    debug 'login failed. password not accepted'
    get_screen_output "$session" | debugoutput

    poweroff_systemd_nspawn
    [[ -e "$securetty_file" ]] && umount "$securetty_file"
    return 1
  fi

  screen -S "$session" -X stuff "PS1=it_works^M"
  last_nonempty_line_of_screen_output_matches "$session" '^it_works$'; result=$?
  if ((result != 0)); then
    debug 'setting prompt to verify login success failed:'
    get_screen_output "$session" | debugoutput
  fi

  poweroff_systemd_nspawn
  [[ -e "$securetty_file" ]] && umount "$securetty_file"

  return $result
}

# vim: ai:ts=2:sw=2:et
