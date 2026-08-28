# The API will not start

**Symptom:** `uvicorn`/`fastapi` exits immediately, or the port never listens.

## 1. Read the last line first

The traceback's **last** line says what happened; the **first frame in your own
code** says where. Do not guess before reading — it has cost hours.

## 2. A missing setting (most common)

```
pydantic_core._pydantic_core.ValidationError: 1 validation error for Settings
API_KEY  Field required
```

By design (ADR-0002): configuration is required, so the app refuses to boot
rather than run misconfigured.

```bash
diff <(grep -o '^[A-Z_]*' .env | sort) <(grep -o '^[A-Z_]*' .env.example | sort)
```

Anything in `.env.example` and not in `.env` is your answer.

⚠️ `.env` is resolved from the **current working directory**, not from
`config.py`. Starting the server from another folder loses it entirely. Always
launch from the repo root.

## 3. A syntax error, or an import that runs code

```bash
uv run python -c "import main; print('imports fine')"
```

Faster than starting the server, and the same import chain.

## 4. The port is already taken

```
[Errno 98] Address already in use
```

```bash
ss -lntp | grep 8006          # who holds it
kill <pid>
```

Usually a server you started earlier and forgot.

## 5. Environment broken after dependency changes

```bash
uv sync                        # make .venv match uv.lock exactly
```

If it is still wrong, rebuild — seconds, not minutes:

```bash
rm -rf .venv && uv sync
```

## 6. It is not the code

The editor buffer is not the file on disk. **Save, then re-run.** This is the
single most frequent cause of "it did not work" in this repo.
