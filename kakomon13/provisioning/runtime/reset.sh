#!/usr/bin/env bash
set -euo pipefail

SQL_DIR=/home/isuren/webapp/sql
for sql in \
  init.sql \
  initial_users.sql \
  initial_livestreams.sql \
  initial_tags.sql \
  initial_livestream_tags.sql \
  initial_reservation_slots.sql \
  initial_reactions.sql \
  initial_ngwords.sql \
  initial_livecomments.sql; do
  mysql --defaults-extra-file=/etc/isuren/kakomon13/mysql.cnf <"${SQL_DIR}/${sql}"
done
/usr/local/libexec/kakomon13-pdns-zone
