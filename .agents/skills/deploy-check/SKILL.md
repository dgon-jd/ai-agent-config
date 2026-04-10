---
name: deploy-check
description: Pre-deployment validation for Railway two-service setup. Use before deploying to verify config, tests, health endpoints, and service readiness.
---

<objective>
Validate that both services (api-monitor and telegram-bot) are ready for Railway deployment by checking configuration, tests, linting, and health endpoints.
</objective>

<quick_start>
Run the checklist below in order. Stop on first failure and report the issue.
</quick_start>

<checklist>

**Step 1 — Environment variables**

Verify all required env vars are set (or `.env` exists locally). Required vars:
- `TELEGRAM_BOT_TOKEN`
- `SUPABASE_URL`
- `SUPABASE_KEY`
- `REDIS_URL`
- `INTERNAL_API_KEY`
- `ENVIRONMENT`

```bash
# Check .env file exists and has required keys
for var in TELEGRAM_BOT_TOKEN SUPABASE_URL SUPABASE_KEY REDIS_URL INTERNAL_API_KEY ENVIRONMENT; do
  grep -q "^${var}=" .env 2>/dev/null && echo "OK: $var" || echo "MISSING: $var"
done
```

**Step 2 — Config validation**

```bash
uv run python -c "from shared.config import get_settings; s = get_settings(); print(f'Config OK: env={s.environment}')"
```

This uses Pydantic validation — any missing or invalid var will throw a clear error.

**Step 3 — Lint check**

```bash
uv run ruff check .
```

**Step 4 — Run tests (fast, no integration)**

```bash
uv run pytest -x -m "not integration and not slow" -q
```

`-x` stops on first failure, `-q` keeps output short.

**Step 5 — Import check for both services**

```bash
uv run python -c "from api_monitor.main import app; print('api-monitor imports OK')"
uv run python -c "from telegram_bot.main import app; print('telegram-bot imports OK')"
```

**Step 6 — Railway config files**

Verify both `railway.toml` files exist and have health checks:

```bash
for svc in api_monitor telegram_bot; do
  if [ -f "$svc/railway.toml" ]; then
    grep -q "healthcheckPath" "$svc/railway.toml" && echo "OK: $svc/railway.toml has healthcheck" || echo "WARN: $svc/railway.toml missing healthcheck"
  else
    echo "MISSING: $svc/railway.toml"
  fi
done
```

**Step 7 — Git status**

```bash
git status --short
git log --oneline -3
```

Check for uncommitted changes and verify latest commits look correct.

</checklist>

<reporting>
After running all steps, summarize:

```
Deploy Check Summary
====================
Environment vars:  OK / X missing
Config validation: OK / FAIL (reason)
Lint:              OK / X issues
Tests:             OK (N passed) / FAIL (N failed)
Service imports:   OK / FAIL (which service)
Railway configs:   OK / WARN (details)
Git status:        clean / N uncommitted changes

Ready to deploy: YES / NO (blockers: ...)
```
</reporting>

<success_criteria>
- All 7 steps pass without errors
- Summary shows "Ready to deploy: YES"
- No uncommitted changes (or user acknowledges them)
</success_criteria>
