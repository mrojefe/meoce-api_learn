# Runbooks

Written calm, read panicking. One file per situation, each starting with the
**symptom you can see**, not the cause — because when it breaks, the symptom is
all you have.

Rules: commands you can paste, in order. Say what a normal result looks like, so
"is this bad?" has an answer. When a step is destructive, say so before it.

| Symptom | Runbook |
|---|---|
| The API will not start | [api-will-not-start.md](api-will-not-start.md) |
| Requests return 500, or bare text | [api-returns-500.md](api-returns-500.md) |
| Cannot reach the database | [database-unreachable.md](database-unreachable.md) |
| The API key must be changed | [rotate-the-api-key.md](rotate-the-api-key.md) |
