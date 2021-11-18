#!/usr/bin/env bash

#
# systemd_nspawn functions
#
# (c) 2015-2021, Hetzner Online GmbH
#

# protect files from systemd
polite_nspawn() {
  if ! [[ -L "$FOLD/hdd/etc/resolv.conf" ]] && ! [[ -e "$FOLD/hdd/etc/resolv.conf" ]]; then
    systemd-nspawn "$@"
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

  systemd-nspawn "$@"

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
    --bind-ro=/etc/resolv.conf:/run/resolvconf/resolv.conf \
    --bind-ro=/etc/resolv.conf:/run/systemd/resolve/stub-resolv.conf \
    --bind-ro="$SYSTEMD_NSPAWN_TMP_DIR/command.fifo:/var/lib/systemd_nspawn/command.fifo" \
    --bind-ro="$SYSTEMD_NSPAWN_TMP_DIR/in.fifo:/var/lib/systemd_nspawn/in.fifo" \
    --bind-ro="$SYSTEMD_NSPAWN_TMP_DIR/out.fifo:/var/lib/systemd_nspawn/out.fifo" \
    --bind-ro="$SYSTEMD_NSPAWN_TMP_DIR/return.fifo:/var/lib/systemd_nspawn/return.fifo" \
    --bind-ro="$SYSTEMD_NSPAWN_TMP_DIR/runner:/usr/local/bin/systemd_nspawn-runner" \
    --bind-ro="$SYSTEMD_NSPAWN_TMP_DIR/systemd_nspawn-runner.service:/etc/systemd/system/systemd_nspawn-runner.service" \
    -D "$FOLD/hdd" &> /dev/null &
  until systemd_nspawn_booted && systemd_nspawn_wo_debug : &> /dev/null; do
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

    polite_nspawn "${dev_bind_args[@]}" --bind-ro=/etc/resolv.conf:/run/resolvconf/resolv.conf \
      --bind-ro=/etc/resolv.conf:/run/systemd/resolve/stub-resolv.conf \
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

# vim: ai:ts=2:sw=2:et
