FROM alpine:3.15

RUN apk --no-cache add borgbackup openssh-client mariadb-client postgresql-client ssmtp py3-pip

ARG BORGMATIC_VERSION=1.5.24

RUN pip3 install --no-cache-dir borgmatic==$BORGMATIC_VERSION

RUN mkdir /etc/borgmatic.d/
RUN mkdir /var/backups/
RUN mkdir ~/.ssh

VOLUME /backups

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
