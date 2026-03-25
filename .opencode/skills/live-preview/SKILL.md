---
name: live-preview
description: Expose a dev server running in this worktree via the Sprite's public URL
user-invocable: false
allowed-tools: Bash(socat *), Bash(kill *), Bash(lsof *), Bash(nohup *), Bash(npm *), Bash(pnpm *), Bash(yarn *), Bash(npx *), Bash(python *), Bash(mix *)
---

## Live Preview

When this project has a dev server (web frontend, API, etc.), you can expose it
to the user via the Sprite's public URL. The Sprite routes all HTTP traffic
arriving at port **8080** to `https://<sprite-name>-<org>.sprites.dev/`.

Your preview URL is available in `$SPRITE_PREVIEW_URL` (empty when running locally).

### How it works

Multiple worktrees share a single Sprite. Each runs its dev server on a
**different port**. A `socat` forwarder on port 8080 points to whichever
worktree the user wants to preview. You control which one is active.

### Step-by-step

1. **Start the dev server** on any free port (not 8080):

   ```bash
   # Pick a deterministic port from the issue id to avoid collisions
   PORT=$((30000 + ($RANDOM % 30000)))
   # Example: Next.js
   nohup npm run dev -- --port $PORT > /tmp/dev-server.log 2>&1 &
   DEV_PID=$!
   echo "Dev server PID=$DEV_PID on port $PORT"
   ```

   Adapt the command to the project's framework (vite, next, mix phx.server, etc.).

2. **Wait for the server to be ready** before forwarding:

   ```bash
   for i in $(seq 1 30); do
     curl -s http://localhost:$PORT > /dev/null && break
     sleep 1
   done
   ```

3. **Forward port 8080 → your dev server port**:

   ```bash
   # Kill any existing forwarder on 8080
   lsof -ti :8080 | xargs -r kill -9 2>/dev/null || true
   # Start socat forwarder
   nohup socat TCP-LISTEN:8080,fork,reuseaddr TCP:localhost:$PORT > /tmp/socat.log 2>&1 &
   SOCAT_PID=$!
   echo "Forwarding 8080 → $PORT (socat PID=$SOCAT_PID)"
   ```

4. **Report the preview URL** so the user can open it:

   ```bash
   echo "Preview: $SPRITE_PREVIEW_URL"
   ```

   Also include the URL in your heartbeat messages so it shows in the dashboard:

   ```bash
   curl -s -X POST "$SYNKADE_API_URL/heartbeat" \
     -H "Authorization: Bearer $SYNKADE_API_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"issue_id":"<issue_id>","status":"working","message":"Preview live at '$SPRITE_PREVIEW_URL'"}'
   ```

5. **Cleanup** when done — stop the forwarder and dev server:

   ```bash
   kill $SOCAT_PID $DEV_PID 2>/dev/null || true
   ```

### Important notes

- **Only one worktree can own port 8080 at a time.** Your `lsof | kill` in step 3
  takes over from whoever had it before. This is expected — the user requested
  your branch.
- If `socat` is not installed, install it: `apt-get update && apt-get install -y socat`
- If `$SPRITE_PREVIEW_URL` is empty, you are running on the local backend —
  just print `http://localhost:$PORT` instead.
- The Sprite URL requires authentication by default (org members + API tokens).
  The user can make it public from the Synkade settings if needed.
