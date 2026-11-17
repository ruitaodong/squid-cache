# squid-cache

A Squid 6 caching proxy for dev and CI environments that caches **Docker/OCI image layers, pip packages, apt/yum packages and wget/curl downloads**, including over HTTPS.

Built on Ubuntu 24.04's `squid-openssl` package (the stock `squid` package and the `ubuntu/squid` image are built without OpenSSL, so they can't do TLS interception).

## How it works

- **Selective TLS interception (SSL bump).** Only hosts worth caching are decrypted: PyPI, Docker Hub and its CDN, `registry.gitlab.com`, GitHub release downloads. Everything else is tunnelled through untouched.
- **Content-addressed cache keys.** Registry layers arrive via short-lived signed URLs. A Store ID helper (`storeid.rules`) rewrites the cache key to the layer's sha256 digest, so every pull of the same layer is a hit.
- **Sensible freshness.** Immutable content (layers, wheels/sdists, `.deb`/`.rpm`) is cached for a year; mutable metadata (manifests/tags, PyPI index, apt/yum indexes) is always revalidated.
- **Built for big, concurrent pulls.** Objects up to 16 GB, collapsed forwarding (many clients, one upstream fetch), and downloads finish into the cache even if the client disconnects.

## Quick start

```bash
docker compose up -d
# The public CA certificate clients must trust is written to ./ca/squid-ca.pem
```

Or without compose:

```bash
docker run -d --name squid-cache -p 3128:3128 \
  -v squid-ca:/etc/squid/ssl -v squid-ssldb:/var/lib/squid \
  -v squid-cache:/var/spool/squid -v "$PWD/ca:/export" \
  ghcr.io/ruitaodong/squid-cache:v1.0.0
```

The image ships with the bundled `squid.conf`; mount your own over `/etc/squid/squid.conf` to customise it.

## Pointing clients at it

On a Debian/Ubuntu host, CI runner or dev box:

```bash
sudo PROXY=http://<proxy-host>:3128 ./client-setup.sh ./ca/squid-ca.pem
```

This trusts the CA system-wide, sets `HTTP(S)_PROXY`/`NO_PROXY`, points pip/requests/Node at the system bundle, and configures git, the Docker daemon and containerd.

Inside other containers, set:

```yaml
environment:
  HTTP_PROXY: http://squid:3128
  HTTPS_PROXY: http://squid:3128
  PIP_CERT: /ca/squid-ca.pem
```

For `docker build`, the proxy variables are passed through automatically, but any tool running inside `RUN` (pip, curl…) also needs the CA inside the build, e.g. via a `--secret` mount.

## Verify caching

```bash
docker compose --profile test run --rm pip-test   # first run: misses
docker compose --profile test run --rm pip-test   # second run: hits
docker compose exec squid grep -E 'TCP_(MEM_)?HIT' /var/log/squid/access.log
```

## Configuration

| What | Where |
|---|---|
| Cache size (default 200 GB) | `cache_dir` in `squid.conf`. Make sure the volume can hold it. |
| Who may use the proxy | `acl localnet` in `squid.conf` (RFC 1918 ranges by default) |
| Hosts to intercept and cache | `acl bump_sites` in `squid.conf` |
| Extra registries/CDNs | Add the blob host to `bump_sites`; the generic Store ID rules already match the standard `docker/registry/v2/blobs` layout |
| CA common name | `SQUID_CA_CN` environment variable (first start only) |

`setup-squid.sh` installs the same setup directly on an Ubuntu/Debian host if you'd rather not use a container.

## Limitations

- **Git over HTTPS isn't cached.** Smart-HTTP git uses POST requests, which Squid can't cache, and git over SSH bypasses the proxy. Use local mirrors or `git clone --reference` instead.
- **Registry blobs served with an `Authorization` header aren't cached** unless the registry marks them public. Registries that redirect blobs to object storage/CDN (Docker Hub, gitlab.com) cache fine.
- **Managed Kubernetes nodes** (e.g. GKE Autopilot) can't be pointed at a proxy for image pulls. Use the registry's own pull-through cache for that, and this proxy for CI, builds and workloads.

## Security

This is a TLS-intercepting proxy. Anyone holding the CA private key can impersonate the intercepted sites to every client that trusts it.

- The key never leaves the `squid-ca` volume; only the public certificate is exported to `./ca`.
- Don't expose port 3128 to the internet; keep it on private networks.
- Intended for dev/CI, not for production traffic.
- `docker compose down -v` deletes the CA. Clients then need the new certificate.

## Images

Images are published to GitHub Container Registry for `linux/amd64` and `linux/arm64` whenever a tag is pushed. The image tag matches the git tag:

```bash
git tag v1.0.0 && git push origin v1.0.0
# -> ghcr.io/ruitaodong/squid-cache:v1.0.0
```

Each build pulls fresh Ubuntu packages, so cutting a new tag is also how you pick up security updates.

## License

MIT
