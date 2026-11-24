FROM ubuntu:26.04

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      squid-openssl openssl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

COPY squid.conf     /etc/squid/squid.conf
COPY storeid.rules  /etc/squid/storeid.rules
COPY entrypoint.sh  /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

VOLUME ["/etc/squid/ssl", "/var/lib/squid", "/var/spool/squid"]
EXPOSE 3128

HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=5 \
  CMD bash -c '</dev/tcp/127.0.0.1/3128' || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
