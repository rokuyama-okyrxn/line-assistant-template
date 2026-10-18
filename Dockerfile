# NOT BUILT OR TESTED YET: no container tool was available on the machine that wrote this.
# Read it line by line before the first real build. Every version is pinned on purpose.
FROM node:24-bookworm-slim

ARG OPENCLAW_VERSION=2026.10.3

# tini: clean shutdown. ca-certificates: HTTPS. git: some npm packages need it.
RUN apt-get update \
 && apt-get install -y --no-install-recommends tini ca-certificates git curl bsdutils \
 && rm -rf /var/lib/apt/lists/*

# OpenClaw 2026.10.3 needs Node 24.16 or newer (its package.json "engines"). Stop the build if the base image is older.
RUN node -e "const [a,b]=process.versions.node.split('.').map(Number); if (a<24 || (a===24 && b<16)) { console.error('Node is too old: ' + process.version); process.exit(1); }"

RUN npm install -g "openclaw@${OPENCLAW_VERSION}" \
 && npm cache clean --force

WORKDIR /app
# Scripts stay owned by root (the container starts as root), so the "node" user cannot rewrite them.
COPY entrypoint.sh chatgpt-signin.sh /app/
COPY config /app/config
COPY workspace /app/workspace
RUN chmod 755 /app/entrypoint.sh /app/chatgpt-signin.sh && chmod -R a+rX /app

# The container STARTS as root only so entrypoint.sh can give the Railway volume (mounted at /data, owned by root)
# to the "node" user; it then drops to "node" (setpriv) before OpenClaw starts. OpenClaw never runs as root.
# (Railway volumes docs, read 2026-10-14: volumes can be root-owned; the alternative is RAILWAY_RUN_UID=0.)
ENV OPENCLAW_STATE_DIR=/data/.openclaw \
    OPENCLAW_WORKSPACE_DIR=/data/workspace \
    OPENCLAW_PLUGIN_VERSION=${OPENCLAW_VERSION}

# The port is taken from Railway's PORT variable if it sets one, otherwise 8080 (see entrypoint.sh).
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/app/entrypoint.sh"]
