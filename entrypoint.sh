#!/bin/sh

if [ -n "$SSH_KEY" ]
then
      echo $SSH_KEY > $HOME/.ssh/id_rsa
      chmod 400 $HOME/.ssh/id_rsa
      cat <<EOF > $HOME/.ssh/config
Host $SSH_HOST
    User root
    IdentityFile $HOME/.ssh/id_rsa
    PreferredAuthentications publickey
EOF
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
EOF
else
      REPO=/backups
fi

echo "Using repo ${REPO}"

borg init -e none $REPO

cat <<EOF  | crontab -
${CRON_TIME:-0 0 * * *} borgmatic -v 1 2>&1
EOF

case "$1" in
 "POSTGRESQL") before_backup="PGPASSWORD=$POSTGRES_PASSWORD pg_dump ${POSTGRES_DATABASE:-$POSTGRES_USER} -h $DB_SERVER_HOST -U $POSTGRES_USER > /var/backups/dump.sql" ;;
 "MYSQL") before_backup="mysqldump ${MYSQL_DATABASE:-$MYSQL_USER} -h $DB_SERVER_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD > /var/backups/dump.sql" ;;
 *) exit 1 ;;
esac

cat <<EOF > /etc/borgmatic.d/backup.yaml
location:
  source_directories:
    - /var/backups/
        
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
  before_backup:
    - $before_backup
  after_backup:
    - rm /var/backups/dump.sql
EOF

crond -f -L /dev/stdout
