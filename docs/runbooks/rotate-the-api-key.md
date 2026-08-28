# Rotate the API key

**When:** the key has appeared anywhere other than `.env` — a chat, a
screenshot, a commit, a colleague's terminal — or on a schedule, or after
someone leaves.

A secret that has been seen is no longer a secret, even if nothing bad has
happened yet.

## 1. Generate a new one

```bash
python3 -c "import secrets; print(secrets.token_urlsafe(32))"
```

Never invent one by hand: human-chosen strings are guessable, and 32 bytes from
`secrets` is not.

## 2. Change it where the API reads it

```bash
nano .env          # API_KEY=<the new value>
```

Then restart the API — `Settings` is read once, at startup, and cached with
`@lru_cache`. Editing `.env` on a running server changes nothing.

## 3. Change it in every caller

Today that is Airflow. Anything holding the old key gets 401 the moment the API
restarts, so plan the order:

- **Short outage acceptable:** change the API, restart, then change the callers.
- **No outage:** accept two keys for a transition window, then remove the old
  one. Not implemented — it needs a list of valid keys rather than one, and is
  the reason per-system keys in a table eventually beat one shared secret
  (ADR-0008).

## 4. Verify

```bash
curl -s -o /dev/null -w "%{http_code}\n" -X POST ".../api/v1/instruments" \
  -H "X-API-Key: OLD_KEY" -H "Content-Type: application/json" -d '{}'   # expect 401

curl -s -o /dev/null -w "%{http_code}\n" ".../api/v1/instruments?limit=1"  # expect 200
```

The old key must fail, and public reads must still work.

## 5. If the key was committed to git

Changing the file is not enough — the old value is still in the history, and on
GitHub. Rotate first (above), *then* decide whether the history needs rewriting.
**Rotating is the fix; scrubbing history is tidying.**
