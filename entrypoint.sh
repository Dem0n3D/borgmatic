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
  ssh-keyscan -t ${SSH_KEY_ALGORITHM:-ecdsa} $SSH_HOST > $HOME/.ssh/known_hosts
  if [ ! -s $HOME/.ssh/known_hosts ]; then
    exit 1
  fi
  cat <<EOF > $HOME/.ssh/config
Host $SSH_HOST
    User ${SSH_USER:-root}
    IdentityFile $HOME/.ssh/id_rsa
    PreferredAuthentications publickey
    ConnectTimeout 30
EOF
else
  REPO=/backups
fi

cat <<EOF | crontab -
${CRON_TIME:-0 0 * * *} borgmatic -v 1 >/var/backups/borg.log 2>&1
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

HOSTNAME="{hostname}"

if [ -n "$MAIL_ADDRESS_TO" ]
then
  cat > /etc/ssmtp/ssmtp.conf << EOF
mailhub=$MAIL_SMTP_SERVER
FromLineOverride=YES
EOF
SUBJECT_SUCCESS="Borg Backup OK for ${BORG_ARCHIVE_NAME:-$HOSTNAME}"
SUBJECT_ERROR="Borg Backup FAIL for ${BORG_ARCHIVE_NAME:-$HOSTNAME}"
SUBJECT_KEY="Borg keyfile for ${BORG_ARCHIVE_NAME:-$HOSTNAME}"
fi

cat <<EOF >/etc/borgmatic.d/backup.yaml
location:
  source_directories:
$(for dir in $BACKUP_LOCATIONS; do printf "    - %s\n" "$dir"; done)

  repositories:
    - ${REPO}

$([ -n "$EXCLUDE_PATTERNS" ] && echo "exclude_patterns:")
$(for ep in $EXCLUDE_PATTERNS; do printf "  - %s\n" "$ep"; done)

storage:
  archive_name_format: '${BORG_ARCHIVE_NAME:-$HOSTNAME}${BORG_ARCHIVE_POSTFIX:--{now:%Y-%m-%dT%H:%M:%S.%f}}'
  lock_wait: ${LOCK_WAIT:-1}

retention:
  keep_daily: ${KEEP_DAILY:-7}
  keep_weekly: ${KEEP_WEEKLY:-4}
  keep_monthly: ${KEEP_MONTHLY:-12}
  keep_yearly: ${KEEP_YEARLY:-4}
  prefix: '${BORG_ARCHIVE_NAME:-$HOSTNAME-}'

consistency:
  checks:
    - repository
    - archives
  prefix: '${BORG_ARCHIVE_NAME:-$HOSTNAME-}'

hooks:
  before_backup:
    - true
$(for bb in $BEFORE_BACKUP; do printf "    - %s\n" "$bb"; done)
  after_backup:
    - true
$(for ab in $AFTER_BACKUP; do printf "    - %s\n" "$ab"; done)
$([ -n "$MAIL_ADDRESS_TO" ] && printf "    - '(printf \"From: %s\\\r\\\nSubject: %s\\\r\\\n\\\r\\\n\"; tail -n 200 /var/backups/borg.log) | ssmtp %s'" "$MAIL_FROM" "$SUBJECT_SUCCESS" "$MAIL_ADDRESS_TO")
$([ -n "$MAIL_ADDRESS_TO" ] && printf "  on_error:")
$([ -n "$MAIL_ADDRESS_TO" ] && printf "    - '(printf \"From: %s\\\r\\\nSubject: %s\\\r\\\n\\\r\\\n\"; tail -n 200 /var/backups/borg.log) | ssmtp %s'" "$MAIL_FROM" "$SUBJECT_ERROR" "$MAIL_ADDRESS_TO")
EOF

echo "Using repo ${REPO}"

if borg init -e "${ENCRYPTION_MODE:-none}" "$REPO" && [ -n "$MAIL_ADDRESS_TO" ] && [ "${ENCRYPTION_MODE:-none}" != "none" ] && [ "${SEND_ENCRYPTION_KEY:-no}" != "no" ]
then
  (printf "From: %s\r\nSubject: %s\r\n\r\n" "$MAIL_FROM" "$SUBJECT_KEY"; borg key export --paper $REPO) | ssmtp "$MAIL_ADDRESS_TO"
fi

cat /etc/borgmatic.d/backup.yaml

crond -f -L /dev/stdout
