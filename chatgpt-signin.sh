#!/bin/sh
# Starts the ChatGPT "device code" sign-in and prints the code and address into the container log
# (Railway: your service > Deployments > Logs), so a beginner needs no typed command.
# Runs in the background after the gateway is up. Skips itself if a ChatGPT sign-in already exists.
# Set CHATGPT_SIGNIN=off to skip (API key only). Output is cleaned of screen-control characters.
OC="${OPENCLAW_BIN:-openclaw}"
PORT="${OPENCLAW_GATEWAY_PORT:-8080}"
say() { printf '%s\n' "[chatgpt-signin] $*"; }

[ "${CHATGPT_SIGNIN:-on}" = "off" ] && { say "Skipped (CHATGPT_SIGNIN=off)."; exit 0; }

# wait for the gateway (up to 3 minutes)
i=0
until curl -fsS -m 3 "http://127.0.0.1:$PORT/healthz" >/dev/null 2>&1; do
  i=$((i+1)); [ "$i" -gt 90 ] && { say "The assistant did not start in time. Not starting the sign-in."; exit 1; }
  sleep 2
done

has_signin() { "$OC" models auth list --provider openai 2>/dev/null | grep -Eq "/(oauth|token)\]"; }

attempt=0
while [ "$attempt" -lt 6 ]; do
  if has_signin; then say "A ChatGPT sign-in is already saved. Nothing to do."; exit 0; fi
  attempt=$((attempt+1))
  say "================================================================"
  say "CHATGPT SIGN-IN (try $attempt of 6). Look for a web address and a short code below."
  say "Open the address on your phone, sign in to ChatGPT, and type the code. You have a few minutes."
  say "================================================================"
  TMO=""; command -v timeout >/dev/null 2>&1 && TMO="timeout 900 "
  # A fifo we hold open keeps stdin alive (not at end-of-file) until the command ends.
  FIFO="${TMPDIR:-/tmp}/chatgpt-signin.$$.fifo"; rm -f "$FIFO"; mkfifo "$FIFO"; exec 3<>"$FIFO"
  # The sign-in command insists on a terminal, so run it inside a pseudo-terminal.
  if script --version 2>&1 | grep -qi util-linux; then
    script -qec "stty cols 200 2>/dev/null; ${TMO}$OC models auth login --provider openai --method device-code" /dev/null <"$FIFO"
  else
    script -q /dev/null sh -c "stty cols 200 2>/dev/null; exec \"$OC\" models auth login --provider openai --method device-code" </dev/null
  fi 2>&1 | sed -u -e 's/\r//g' -e 's/\x1b\[[0-9;?]*[a-zA-Z]//g' -e 's/\x1b\][^\x07]*\x07//g' -e '/^.\{0,1\}$/d' -e 's/^/[chatgpt-signin] /'
  exec 3>&-; rm -f "$FIFO"
  if has_signin; then say "ChatGPT sign-in saved. Your assistant can use your plan now."; exit 0; fi
  say "Not signed in yet. Trying again in 2 minutes."
  sleep 120
done
say "Giving up for now. Redeploy to try again, or use the OpenAI API key (Step 4)."
exit 0
