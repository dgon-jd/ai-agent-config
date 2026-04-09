---
name: run-tests
description: Run pytest test suites with uv. Use when running tests, checking coverage, or validating specific test categories.
---

<objective>
Run the project's pytest suite using `uv run pytest` with the correct flags, coverage targets, and category filters.
</objective>

<quick_start>
Determine what the user wants, then run the appropriate command:

- **All tests**: `uv run pytest`
- **All tests with coverage**: `uv run pytest --cov=shared --cov=api_monitor --cov=telegram_bot --cov-report=term-missing`
- **Specific category**: `uv run pytest tests/test_{category}.py`
- **Specific test**: `uv run pytest tests/test_{file}.py::TestClass::test_name`
</quick_start>

<commands>

**Run all tests:**
```bash
uv run pytest
```

**Run all tests with coverage report:**
```bash
uv run pytest --cov=shared --cov=api_monitor --cov=telegram_bot --cov-report=term-missing
```

**Run with HTML coverage report:**
```bash
uv run pytest --cov=shared --cov=api_monitor --cov=telegram_bot --cov-report=html
```

**Run a specific test category:**
```bash
uv run pytest tests/test_config.py            # Configuration
uv run pytest tests/test_database.py           # Database CRUD
uv run pytest tests/test_models.py             # Data models
uv run pytest tests/test_utils.py              # Utilities
uv run pytest tests/test_integration.py        # Integration
uv run pytest tests/test_performance.py        # Performance benchmarks
uv run pytest tests/test_change_detector.py    # Change detection
uv run pytest tests/test_notifier.py           # Notification sending
uv run pytest tests/test_stream_consumer.py    # Redis stream consumer
uv run pytest tests/test_redis_streams.py      # Redis streams
uv run pytest tests/test_subscription_flow.py  # Subscription flow
uv run pytest tests/test_message_builder.py    # Message formatting
uv run pytest tests/test_multi_source_client.py # Multi-source API client
uv run pytest tests/test_cache_manager.py      # Cache management
uv run pytest tests/test_cleanup.py            # Data cleanup
uv run pytest tests/test_health_endpoints.py   # Health checks
uv run pytest tests/test_observability.py      # Observability
```

**Run only integration or slow tests:**
```bash
uv run pytest -m integration
uv run pytest -m slow
```

**Exclude integration/slow tests:**
```bash
uv run pytest -m "not integration and not slow"
```

**Run with verbose output (useful for debugging failures):**
```bash
uv run pytest -v
```

**Run last failed tests only:**
```bash
uv run pytest --lf
```

**Stop on first failure:**
```bash
uv run pytest -x
```
</commands>

<notes>
- asyncio_mode is set to `auto` in pyproject.toml — no need for `@pytest.mark.asyncio`
- Coverage targets: `shared`, `api_monitor`, `telegram_bot`
- Test markers defined: `integration` (require real services), `slow`
- All tests live in `tests/` directory
</notes>

<success_criteria>
- Tests run without import or collection errors
- Coverage report shows covered modules when requested
- Specific category runs only the intended tests
</success_criteria>
