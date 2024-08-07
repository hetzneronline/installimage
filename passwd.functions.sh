#!/usr/bin/env bash

#
# passwd functions
#
# (c) 2023, Hetzner Online GmbH
#

installed_os_set_root_password_hash() {
  local value="$1"
  sed -i "s:^root\:[^:]*:root\:$value:g" "$FOLD/hdd/etc/shadow"
}

rescue_root_password_hash() {
  getent shadow root | cut -d : -f 2
}

restore_shadow() {
  [[ -e /etc/shadow.installimage_bak ]] || return
  mv /etc/shado{w.installimage_bak,w}
}

rescue_password_hashing_algo() {
  rescue_root_password_hash | cut -d $ -f 2
}

rescue_gen_password_hash() {
  local password="$1"
  local rescue_algo
  if ! rescue_algo="$(rescue_password_hashing_algo)"; then
    debug 'internal error: get rescue password hashing algo failed'
    return 1
  fi
  cp /etc/shado{w,w.installimage_bak}
  local passwd_cmd='passwd'
  if [[ -e /usr/bin/passwd_real ]]; then passwd_cmd='passwd_real'; fi
  PASSWD_CMD="$passwd_cmd" "$SCRIPTPATH/util/passwd$rescue_algo.sh" <<< "$password"$'\n'"$password" &> /dev/null || return 1
  local password_hash
  if ! password_hash="$(rescue_root_password_hash)"; then
    debug 'internal error: get rescue root password hash failed'
    restore_shadow
    return 1
  fi
  restore_shadow || return 1
  echo "$password_hash"
}

rescue_password_hashing_algo_supported_by_installed_os() {
  # prereqs
  if ! execute_chroot_command_wo_debug 'getent passwd nobody' &> /dev/null; then
    debug 'internal error: installed os does not have a nobody user'
    return 1
  fi
  local su_path
  if ! su_path="$(execute_chroot_command_wo_debug 'command -v su')"; then
    debug 'internal error: installed os su path not found'
    return 1
  fi

  local random_password
  random_password="$(generate_password)"
  local password_hash
  if ! password_hash="$(rescue_gen_password_hash "$random_password")"; then
    debug 'internal error: rescue gen password hash failed'
    return 1
  fi
  if ! installed_os_set_root_password_hash "$password_hash"; then
    debug 'internal error: installed os set root password hash failed'
  fi

  if [[ "$IAM" == ubuntu ]] && ((IMG_VERSION < 2004)); then
    verify_machinectl_login_works "$random_password" && return
  elif [[ "$IAM" == debian ]] && ((IMG_VERSION >= 900)) && ((IMG_VERSION < 1000)); then
    verify_machinectl_login_works "$random_password" && return
  else
    execute_chroot_command_wo_debug "su nobody -s '$su_path'" <<< "$random_password" &> /dev/null && return
  fi

  return 1
}

check_rescue_password_hashing_algo_supported_by_installed_os() {
  rescue_password_hashing_algo_supported_by_installed_os && return

  local rescue_algo
  if ! rescue_algo="$(rescue_password_hashing_algo)"; then
    debug 'internal error: get rescue password hashing algo failed'
    echo "\n\n\e[1;31mInternal error, contact $COMPANY support\e[0m\n" >&2
    return 1
  fi

  local random_password
  random_password="$(generate_password)"
  if ! execute_chroot_command_wo_debug passwd <<< "$random_password"$'\n'"$random_password" &> /dev/null; then
    debug 'internal error: installed os set random password failed'
    echo "\n\n\e[1;31mInternal error, contact $COMPANY support\e[0m\n" >&2
    return 1
  fi

  local installed_os_algo
  if ! installed_os_algo="$(execute_chroot_command_wo_debug 'getent shadow root | cut -d : -f 2 | cut -d $ -f 2')"; then
    debug 'internal error: get installed os default password hashing algo failed'
    echo "\n\n\e[1;31mInternal error, contact $COMPANY support\e[0m\n" >&2
    return 1
  fi

  debug "aborting installation: unsupported password hashing algo"
  {
    echo "the image you are trying to install does not support the $rescue_algo password hashing algorithm."
    echo 'to fix this you need to reset the root password using a suitable algorithm.'
    echo "the image used defaults to type $installed_os_algo hashes."
    echo "you can use $(readlink -f $SCRIPTPATH/util)/passwd$installed_os_algo.sh to set a password using this algorithm"
  } | debugoutput

  {
    echo -e "\n\n\e[1;31mThe image you are trying to install does not support the"
    echo 'password hashing algorithm with which the currently set root'
    echo -e "password is hashed.\e[0m\n"
    echo -e "You need to fix this mismatch before you can rerun installimage.\n"
    echo -e "\e[1;33mYou can run\e[0m $(readlink -f $SCRIPTPATH/util)/passwd$installed_os_algo.sh"
    echo -e "\e[1;33mto set a new root password using the images default algorithm.\e[0m\n"
  } >&2

  return 1
}

# vim: ai:ts=2:sw=2:et
