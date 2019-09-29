#!/bin/sh

IFS=';'

if [ -n "$SSH_KEY" ]
then
  echo $SSH_KEY > $HOME/.ssh/id_rsa
  chmod 400 $HOME/.ssh/id_rsa
fi

if [ -n "$SSH_REPO" ]
then
  REPO=$SSH_REPO
  ssh-keyscan -t ecdsa $SSH_HOST > $HOME/.ssh/known_hosts
  cat <<EOF > $HOME/.ssh/config
Host $SSH_HOST
    User root
    IdentityFile $HOME/.ssh/id_rsa
    PreferredAuthentications publickey
    ConnectTimeout 30
EOF
else
  REPO=/backups
fi

echo "Using repo ${REPO}"

borg init -e "${ENCRYPTION_MODE:-none}" "$REPO"

cat <<EOF | crontab -
${CRON_TIME:-0 0 * * *} borgmatic -v 1 2>&1
EOF

case $DB_TYPE in
"POSTGRESQL")
  if [ -n "$POSTGRES_PASSWORD" ]
  then
    printf "%s:%s:%s:%s:%s\n" "${DB_SERVER_HOST}" "${DB_SERVER_PORT:-5432}" "${POSTGRES_DATABASE:-$POSTGRES_USER}" "$POSTGRES_USER" "$POSTGRES_PASSWORD" > $HOME/.pgpass
    chmod 600 $HOME/.pgpass
  fi
  BEFORE_BACKUP="pg_dump ${POSTGRES_DATABASE:-$POSTGRES_USER} -h $DB_SERVER_HOST -U $POSTGRES_USER -w > /var/backups/dump.sql"
  BACKUP_LOCATIONS="/var/backups/dump.sql;$BACKUP_LOCATIONS"
  ;;
"MYSQL")
  if [ -n "$MYSQL_PASSWORD" ]
  then
    printf "[client]\npassword=%s\n" "$MYSQL_PASSWORD" > $HOME/.my.cnf
    chmod 600 $HOME/.my.cnf
  fi
  BEFORE_BACKUP="mysqldump ${MYSQL_DATABASE:-$MYSQL_USER} -h $DB_SERVER_HOST -u $MYSQL_USER > /var/backups/dump.sql"
  BACKUP_LOCATIONS="/var/backups/dump.sql;$BACKUP_LOCATIONS"
  ;;
*)
  ;;
esac

cat <<EOF >/etc/borgmatic.d/backup.yaml
location:
  source_directories:
$(for dir in $BACKUP_LOCATIONS; do printf "    - %s\n" "$dir"; done)

  repositories:
    - ${REPO}
  
retention:
  keep_daily: ${KEEP_DAILY:-7}
  keep_weekly: ${KEEP_WEEKLY:-4}
  keep_monthly: ${KEEP_MONTHLY:-12}
  keep_yearly: ${KEEP_YEARLY:-4}

consistency:
  checks:
    - repository
    - archives

hooks:
$([ -n "$BEFORE_BACKUP" ] && echo "  before_backup:")
$(for bb in $BEFORE_BACKUP; do printf "    - %s\n" "$bb"; done)
  after_backup:
    - rm -f /var/backups/dump.sql
EOF

cat /etc/borgmatic.d/backup.yaml

crond -f -L /dev/stdout
