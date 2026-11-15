PORT ?= 8765

.PHONY: web
web:
	uv run --locked --group web python scripts/run_web.py --port "$(PORT)"
