FROM alpine:3.10

RUN apk --no-cache add borgbackup openssh-client mariadb-client postgresql-client

ARG BORGMATIC_VERSION=1.2.*

RUN pip3 install --no-cache-dir borgmatic==$BORGMATIC_VERSION

RUN mkdir /etc/borgmatic.d/
RUN mkdir /var/backups/
RUN mkdir ~/.ssh

VOLUME /backups

ENV BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK yes

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
