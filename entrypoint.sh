#!/bin/sh
# Runs every time the container starts. Plain sh, no secrets printed.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
OC="${OPENCLAW_BIN:-openclaw}"
STATE="${OPENCLAW_STATE_DIR:-/data/.openclaw}"
WORKSPACE="${OPENCLAW_WORKSPACE_DIR:-/data/workspace}"
PLUGIN_VERSION="${OPENCLAW_PLUGIN_VERSION:-2026.10.3}"   # keep equal to the OpenClaw version in the Dockerfile
export OPENCLAW_STATE_DIR="$STATE" OPENCLAW_WORKSPACE_DIR="$WORKSPACE"
export OPENCLAW_CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-$STATE/openclaw.json}"
# Port: an explicit OPENCLAW_GATEWAY_PORT wins, then Railway's PORT, then 8080. (Railway's health check and public domain follow PORT.)
export OPENCLAW_GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-${PORT:-8080}}"

say() { printf '%s\n' "[template] $*"; }

# 0. If started as root (the Dockerfile does this so the volume can be given to "node"), fix the folders'
#    owner and then run this same script as "node". OpenClaw itself never runs as root.
if [ "$(id -u)" = "0" ]; then
  mkdir -p "$STATE" "$WORKSPACE"
  chown -R node:node "$STATE" "$WORKSPACE" 2>/dev/null || say "Warning: could not change the owner of the data folders."
  if command -v setpriv >/dev/null 2>&1 && setpriv --reuid=node --regid=node --init-groups -- true 2>/dev/null; then
    export HOME=/home/node
    exec setpriv --reuid=node --regid=node --init-groups -- "$0" "$@"
  fi
  say "STOP. Could not switch to the node user. The assistant will not run as root. Check the Dockerfile and the Railway volume."
  exit 1
fi

# 1. Required values. Say which ones are missing, by name only.
missing=""
for name in OPENCLAW_GATEWAY_TOKEN LINE_CHANNEL_SECRET LINE_CHANNEL_ACCESS_TOKEN; do
  eval "value=\${$name:-}"
  [ -n "$value" ] || missing="$missing $name"
done
if [ -n "$missing" ]; then
  say "STOP. These Railway variables are empty:$missing"
  say "Open Railway > your service > Variables, fill them in, then redeploy."
  exit 1
fi

# 2. Folders on the volume.
mkdir -p "$STATE" "$WORKSPACE"

# 3. The LINE plugin lives in the state folder, so it survives redeploys. Install it only if missing.
if ! "$OC" plugins inspect line >/dev/null 2>&1; then
  say "Installing the LINE plugin (version $PLUGIN_VERSION)..."
  "$OC" plugins install "@openclaw/line@$PLUGIN_VERSION"
else
  say "LINE plugin already installed."
fi

# 4. Instruction files for the assistant. AGENTS.md is RESET from the template at EVERY start (edits to it are lost
#    on purpose: one known set of rules). SOUL.md and USER.md are copied only if missing, so they can hold the friend's manner.
cp "$HERE/workspace/AGENTS.md" "$WORKSPACE/AGENTS.md"; say "AGENTS.md reset from the template."
for f in SOUL.md USER.md; do
  [ -f "$WORKSPACE/$f" ] || { cp "$HERE/workspace/$f" "$WORKSPACE/$f"; say "Created $f"; }
done

# 5. Apply the settings. Objects merge, so values the app saved itself (for example the approved owner) stay.
"$OC" config patch --file "$HERE/config/openclaw.base.json5" >/dev/null

# 5a. Google Maps (Google's Maps Grounding Lite) is an OPTIONAL add-on. It ships OFF: on only if a key is set.
#     An empty key always switches it off again, so an earlier start cannot leave it on with a missing key.
if [ -n "${GOOGLE_MAPS_API_KEY:-}" ]; then
  "$OC" config patch --file "$HERE/config/maps.json5" >/dev/null
  say "Google Maps is on."
else
  "$OC" config patch --file "$HERE/config/maps-off.json5" >/dev/null
  say "Google Maps is off: GOOGLE_MAPS_API_KEY is empty. This is the normal first set-up; places and routes are an optional add-on."
fi

# 5a2. Web tools (web_search, web_fetch) are ON by default. WEB_TOOLS=off removes both. No address controls.
# Only the exact value "off" turns them off; empty, missing or anything else leaves them on.
if [ "${WEB_TOOLS:-}" = "off" ]; then
  "$OC" config patch --file "$HERE/config/web-tools-off.json5" >/dev/null
  say "Web tools are OFF (WEB_TOOLS=off): no web search, no web page reading."
else
  "$OC" config patch --file "$HERE/config/web-tools-on.json5" >/dev/null
  say "Web tools are on."
fi

# 5b. Optional: only the owner may chat (no pairing command needed).
if [ -n "${LINE_OWNER_USER_ID:-}" ]; then
  "$OC" config patch --file "$HERE/config/owner-allowlist.json5" >/dev/null
  say "Only the LINE user in LINE_OWNER_USER_ID can chat with the assistant."
else
  say "LINE_OWNER_USER_ID is empty: the first person who messages gets a pairing code you must approve."
fi

# 5c. The public control page is OFF by default (a beginner does not need it; fewer ways in).
#     Set OPENCLAW_CONTROL_UI=on to keep it. A remote browser must then be approved with `openclaw devices approve`.
if [ "${OPENCLAW_CONTROL_UI:-off}" != "on" ]; then
  "$OC" config patch --file "$HERE/config/ui-off.json5" >/dev/null
  say "Control page is off."
else
  "$OC" config patch --file "$HERE/config/ui-on.json5" >/dev/null
  say "Control page is ON (each new browser needs a typed approval command)."
fi

# 5d. Optional backup: save the OpenAI API key as a sign-in profile. OpenClaw tries a ChatGPT sign-in first and
#     this key second (documented default order: OAuth, then API key). Saved again at every start, so a new key
#     in Railway Variables takes effect after a redeploy.
if [ -n "${OPENAI_API_KEY:-}" ]; then
  printf '%s\n' "$OPENAI_API_KEY" | "$OC" models auth paste-api-key --provider openai --profile-id openai:api-key-backup >/dev/null 2>&1 \
    && say "OpenAI API key saved as the backup sign-in." \
    || say "Warning: could not save OPENAI_API_KEY."
fi

# 5e. For tests only: an extra settings file applied LAST (the local test points the AI and Maps at fake local servers).
if [ -n "${OPENCLAW_EXTRA_PATCH:-}" ]; then "$OC" config patch --file "$OPENCLAW_EXTRA_PATCH" >/dev/null; fi
"$OC" config validate

# For tests only: stop here without starting the gateway.
if [ "${TEMPLATE_DRY_RUN:-}" = "1" ]; then say "Dry run: settings applied, not starting."; exit 0; fi

# 6. ChatGPT sign-in helper in the background: prints the sign-in code into the log once the gateway is up.
# Only an unset variable or the exact value "on" starts the helper. An EMPTY value (a friend cleared it by mistake) or "off" or any typo does not.
case "${CHATGPT_SIGNIN-on}" in
  on) "$HERE/chatgpt-signin.sh" & echo $! > "$STATE/chatgpt-signin.pid" ;;
  *) say "ChatGPT sign-in helper is off (CHATGPT_SIGNIN is not \"on\"). The OpenAI API key is the only AI." ;;
esac

# 7. Start. (exec so the container stops cleanly.)
say "Starting the assistant on port $OPENCLAW_GATEWAY_PORT."
exec "$OC" gateway run
