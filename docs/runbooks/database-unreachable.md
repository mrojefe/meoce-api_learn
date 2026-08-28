# Cannot reach the database

**Symptom:** `connection refused`, or a call that hangs and never returns.

## 1. Is it the network or the database?

```bash
tailscale status                                   # both machines up?
ss -lntp | grep 5433                               # is anything listening?
psql -h 100.101.79.4 -p 5433 -U postgres postgres  # can psql get in?
```

If `psql` connects, the problem is in the API, not the network.

## 2. The port mapping

Staging Postgres runs in Coolify and is published in the compose file:

```yaml
ports:
  - '100.101.79.4:5433:5432'
     └ which interface  └ host port  └ port inside the container
```

- `5433` is the port to connect to. `5432` exists only inside the container.
- The first field is **which of my addresses to listen on** — never who is
  allowed. `100.101.79.4` is this VPS's Tailscale address, so the port is
  reachable across the tailnet and invisible from the public internet.
- ⚠️ **Never `0.0.0.0`.** That is every interface including the public one, and
  an exposed Postgres is found by scanners within minutes.
- `ports`, plural. `port:` is silently ignored by compose.

After editing, **Restart** the service in Coolify (there is no Redeploy button
for this stack).

## 3. Which stack is which

```
supabase-db-bixm93wpgq9ywu3lq13diiul   dbmeoce-staging   preview      ← STAGING, use this
supabase-db-czwhmo6nj68ptorflflw44t5   supabase-meo      production   ← DO NOT TOUCH
```

## 4. The API starts but every query fails

The pool is opened by the **lifespan**, so it only exists under uvicorn. In a
notebook or a script, open it yourself:

```python
from app.core.database import open_pool
open_pool()
```

`RuntimeError: pool not opened — did the app start correctly?` is that message
doing its job.

## 5. Known and accepted

`show ssl` is **off** — the connection is not encrypted by Postgres. Acceptable
only because Tailscale (WireGuard) encrypts the tunnel underneath. If the API
ever moves to a machine that reaches the database another way, this must be
fixed first.
