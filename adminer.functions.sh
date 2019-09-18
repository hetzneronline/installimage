#!/usr/bin/env bash

#
# adminer functions
#
# (c) 2019, Hetzner Online GmbH
#

setup_adminer() {
  debug '# setup adminer'
  local password="$(generate_password)"
  create_mysql_user 'adminer' "$password" || return 1
  {
    echo 'Adminer access data:'
    echo '  Username: adminer'
    echo "  Password: $password"
  } >> "$FOLD/hdd/password.txt"
}

# vim: ai:ts=2:sw=2:et
