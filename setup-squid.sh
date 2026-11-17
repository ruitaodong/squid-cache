#!/usr/bin/env bash
# Install and initialise the Squid cache on Ubuntu/Debian.
# Run as root from the directory containing squid.conf and storeid.rules.
set -euo pipefail

apt-get update
apt-get install -y squid-openssl openssl

# 1. Create the interception CA (keep the key private!)
install -d -m 750 -o proxy -g proxy /etc/squid/ssl
if [[ ! -f /etc/squid/ssl/squid-ca.key ]]; then
  openssl req -new -newkey rsa:4096 -sha256 -days 825 -nodes -x509 \
    -subj "/CN=Dev Squid Cache CA" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -keyout /etc/squid/ssl/squid-ca.key \
    -out    /etc/squid/ssl/squid-ca.pem
  chown proxy:proxy /etc/squid/ssl/squid-ca.*
  chmod 600 /etc/squid/ssl/squid-ca.key
fi

# 2. Certificate cache for generated host certs
rm -rf /var/lib/squid/ssl_db
install -d -o proxy -g proxy /var/lib/squid
/usr/lib/squid/security_file_certgen -c -s /var/lib/squid/ssl_db -M 16MB
chown -R proxy:proxy /var/lib/squid/ssl_db

# 3. Config
install -m 644 squid.conf    /etc/squid/squid.conf
install -m 644 storeid.rules /etc/squid/storeid.rules
squid -k parse

# 4. Initialise cache dirs and start
systemctl stop squid || true
install -d -o proxy -g proxy /var/spool/squid
squid -z --foreground
systemctl enable --now squid

echo
echo "Distribute this CA certificate to clients:"
echo "  /etc/squid/ssl/squid-ca.pem"
