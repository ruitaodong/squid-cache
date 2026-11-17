#!/usr/bin/env bash
# Prepares CA, cert DB and cache dirs on first start, then runs Squid in the foreground.
set -euo pipefail

CONF=/etc/squid/squid.conf
SSL_DIR=/etc/squid/ssl
SSL_DB=/var/lib/squid/ssl_db
SPOOL=/var/spool/squid
EXPORT=/export

# 1. Interception CA (generated once, persisted in the squid-ca volume)
mkdir -p "$SSL_DIR"
if [[ ! -f "$SSL_DIR/squid-ca.key" ]]; then
  echo "Generating Squid interception CA..."
  openssl req -new -newkey rsa:4096 -sha256 -days 825 -nodes -x509 \
    -subj "/CN=${SQUID_CA_CN:-Dev Squid Cache CA}" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -keyout "$SSL_DIR/squid-ca.key" -out "$SSL_DIR/squid-ca.pem"
fi
chown -R proxy:proxy "$SSL_DIR"
chmod 600 "$SSL_DIR/squid-ca.key"

# Publish only the public certificate for clients
if [[ -d "$EXPORT" ]]; then
  cp "$SSL_DIR/squid-ca.pem" "$EXPORT/squid-ca.pem"
  chmod 644 "$EXPORT/squid-ca.pem"
fi

# 2. Generated-certificate database
mkdir -p /var/lib/squid
if [[ ! -f "$SSL_DB/index.txt" ]]; then
  rm -rf "$SSL_DB"
  /usr/lib/squid/security_file_certgen -c -s "$SSL_DB" -M 16MB
fi
chown -R proxy:proxy /var/lib/squid

# 3. Cache and log dirs
mkdir -p "$SPOOL" /var/log/squid /run/squid
chown -R proxy:proxy "$SPOOL" /var/log/squid /run/squid

squid -k parse -f "$CONF"

if [[ ! -d "$SPOOL/00" ]]; then
  echo "Initialising cache directories..."
  squid -z --foreground -f "$CONF"
fi

rm -f /run/squid.pid /run/squid/squid.pid

# 4. Run in the foreground; -d 1 sends cache.log-level messages to stderr
exec squid -N -d 1 -f "$CONF" "$@"
