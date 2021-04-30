#!/usr/bin/env bash

#
# systemd_nspawn functions
#
# (c) 2015-2018, Hetzner Online GmbH
#

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
  systemd-nspawn -b \
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
    local restore_resolv_conf=0
    if [[ -e "$FOLD/hdd/etc/resolv.conf" ]]; then
      cp "$FOLD/hdd/etc/resolv.conf" "$FOLD/hdd/etc/resolv.conf.bak" || return 1
      restore_resolv_conf=1
    fi
    systemd-nspawn --bind=/dev --bind-ro=/etc/resolv.conf:/run/resolvconf/resolv.conf \
      --bind-ro=/etc/resolv.conf:/run/systemd/resolve/stub-resolv.conf \
      -D "$FOLD/hdd" \
      '--property=DeviceAllow=block-* rwm' \
      '--property=DeviceAllow=/dev/mapper/control rwm' \
      -q /usr/bin/env bash -c "$*"
    r=$?
    if [[ -e "$FOLD/hdd/etc/resolv.conf.bak" ]]; then
      if ((restore_resolv_conf == 1)); then
        mv "$FOLD/hdd/etc/resolv.conf.bak" "$FOLD/hdd/etc/resolv.conf" || return 1
      fi
    fi
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
