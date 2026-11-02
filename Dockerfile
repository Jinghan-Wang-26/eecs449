FROM oven/bun:1.3.11 AS bun
FROM caddy:2.10.2 AS caddy
FROM python:3.13-slim-bookworm

ENV PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PORT=10000 \
    JAC_DATA_PATH=/var/data \
    LLM_BACKEND=api \
    HOME=/home/cartcompass
WORKDIR /app
RUN sed -i s,http://deb.debian.org,https://deb.debian.org,g /etc/apt/sources.list.d/debian.sources \
    && apt-get -o Acquire::ForceIPv4=true -o Acquire::https::Timeout=20 update \
    && apt-get -o Acquire::ForceIPv4=true -o Acquire::https::Timeout=20 install -y --no-install-recommends ca-certificates gosu tini \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 10001 cartcompass
COPY --from=bun /usr/local/bin/bun /usr/local/bin/bun
COPY --from=caddy /usr/bin/caddy /usr/local/bin/caddy
# BuildKit preserves Caddy's privileged-port capability. Render restricts it,
# causing exec to fail with EPERM even for `caddy hash-password`. We use PORT
# >= 1024, so remove the unnecessary capability before dropping privileges.
RUN python -c 'import os; p="/usr/local/bin/caddy"; os.removexattr(p, "security.capability") if "security.capability" in os.listxattr(p) else None' \
    && gosu cartcompass caddy version
COPY requirements.txt ./
# Prefer IPv4 inside this container; retain IPv6 fallback and TLS verification.
RUN printf 'precedence ::ffff:0:0/96 100\n' >> /etc/gai.conf \
    && pip install --no-cache-dir -r requirements.txt
COPY --chown=cartcompass:cartcompass . .
# Both frontend assets and Jac caches are built without credentials or user data.
RUN chown cartcompass:cartcompass /app \
    && gosu cartcompass jac build main.jac \
    && rm -rf /app/.jac/data \
    && chmod +x /app/deploy/start.sh
EXPOSE 10000
ENTRYPOINT ["/usr/bin/tini", "--", "/app/deploy/start.sh"]
