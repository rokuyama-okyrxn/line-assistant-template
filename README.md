# Assistant template (OpenClaw on Railway, LINE)

A starting point for a beginner's own AI assistant in LINE. One-to-one text chat only. Built 2026-10-14 for the guide in `../guide-src/`. Design and reasons: `../design/template-design.md`.

**Status:** the settings, start-up script and instruction files were **tested locally** with fake keys (see "Local test record"). The `Dockerfile` and `railway.toml` were **not built or run** (no container tool on the build machine; no Railway account used). Nothing here has talked to LINE, OpenAI, Google or Railway.

## What is in this folder

| File | Purpose |
|---|---|
| `Dockerfile` | Image: Node 24 and OpenClaw 2026.10.3, pinned. Starts as root only to fix the volume owner, then runs as `node`; the start scripts stay root-owned. |
| `railway.toml` | Build with the Dockerfile; health check `/healthz`; restart on failure (10 tries). (Railway is replacing this file type; it works until 2026-12-01.) |
| `entrypoint.sh` | At every start: check the required variables, install the LINE plugin if missing, reset `AGENTS.md` from the template (every start; SOUL.md and USER.md only if missing), apply the web-tools setting (`WEB_TOOLS=on` removes web search and page reading), apply the settings (control page off, optional owner-only list and backup key) and start the ChatGPT sign-in helper, start. |
| `chatgpt-signin.sh` | In the background after start: prints a ChatGPT sign-in code and address into the log (Railway: Deployments > Logs). |
| `config/maps.json5`, `maps-off.json5` | Google's Maps Grounding Lite (remote MCP, key in the `X-Goog-Api-Key` header from `GOOGLE_MAPS_API_KEY`); applied only when the key is set; Maps is an optional add-on and ships off (empty key = `maps-off.json5`). |
| `config/openclaw.base.json5` | The settings. Secrets are `${NAME}` placeholders read from the environment. |
| `workspace/AGENTS.md`, `SOUL.md`, `USER.md` | The assistant's instructions and manner (Japanese and English). `AGENTS.md` is overwritten at every start (a friend's edits to it are lost on purpose); SOUL.md and USER.md are copied once. |
| `.env.example` | Every variable, where each value comes from, which are secret. |
| `local-test/` | Test rig (not for friends): fake AI server, signed LINE message sender, sandboxed run, `test-all.sh`. |

## Run it on Railway (for Royce, once)

Railway keeps variables and the volume in its template composer, not in repo files (Railway docs, read 2026-10-14). In the composer: add a service from this repo's GitHub address; add the variables from `.env.example` (use `${{secret(64, "abcdef0123456789")}}` for `OPENCLAW_GATEWAY_TOKEN`; leave the LINE and OpenAI ones for the friend to fill in; **do not add `GOOGLE_MAPS_API_KEY` to the composer**: Maps ships off, and the friend adds that one variable by hand only if they follow the guide's optional "Add Maps later" page); turn on public HTTP networking (the assistant listens on Railway's `PORT`, or 8080 if none is set); health check path `/healthz`; attach a volume at `/data`. The container starts as root only to give the volume to the `node` user and then runs OpenClaw as `node` (this root-then-drop step is untested; no root account was available on the build machine). Exact button names: unverified, see `../BLOCKED.md`.

## Run the local test (no accounts, no keys)

```bash
cd template/local-test
npm install                 # once; installs OpenClaw and the test tools inside this folder
./test-all.sh               # about 13 minutes; writes TEST-RECORD.md
```

What it does: runs the real `entrypoint.sh` with fake values; starts a fake AI server on 127.0.0.1; starts OpenClaw under `sandbox-exec` so it cannot reach any network except localhost; sends signed fake LINE messages; checks the results. Only the first dry run uses the network (the public npm registry, to fetch the LINE plugin; no account). `HOME` and the OpenClaw state folder are redirected into `local-test/`.

Manual commands: `./run-gateway.sh [--fresh]`, `./stop-gateway.sh`, `source env.sh` then `oc pairing list line`.

## Update on purpose

Change the version number in `Dockerfile` (`OPENCLAW_VERSION`), rerun `local-test` with the new `npm install openclaw@<version> @openclaw/line@<version>`, read the release notes, then redeploy. Do not use `latest`.

## Things that only a real deploy can answer

See the end of `../design/template-design.md` (section 9) and `local-test/TEST-RECORD.md`.
