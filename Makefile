# BODYGUARD INC. — Autonomous Gemini Agent & CI Quality Gate Makefile
.PHONY: help setup-env security check test-unit test-mp test-perf verify-all

PYTHON := python3

help:
	@echo "BODYGUARD INC. — Available Targets:"
	@echo "  make setup-env  - Check/install Godot 4.3+, gdlint, and configure Git hooks"
	@echo "  make security   - Scan repo for leaked API keys, secrets, junk files, and >10MB bloat"
	@echo "  make check      - Security guard + strict GDScript static check + netcode authority audit"
	@echo "  make test-unit  - Unit tests (VIP state machine, 300-tick ragdoll stability, voice mock)"
	@echo "  make test-mp    - Headless 1 Host + 2 Clients localhost co-op smoke simulation"
	@echo "  make test-perf  - 1,000-tick party scene benchmark & orphan-node leak check"
	@echo "  make verify-all - Full autonomous quality gate (all of the above)"

setup-env:
	@./scripts/setup_env.sh

security:
	@echo ">>> [make security] Secret, API key, junk & bloat guard"
	@$(PYTHON) scripts/secret_guard.py --all

check: security
	@echo ">>> [make check] Static typing, linting & netcode security audit"
	@$(PYTHON) scripts/gd_static_check.py
	@$(PYTHON) .agent/skills/multiplayer-netcode-guard/scripts/audit_netcode.py

test-unit:
	@echo ">>> [make test-unit] Unit, ragdoll stability & voice lip-sync tests"
	@$(PYTHON) tests/unit/run_unit_tests.py

test-mp:
	@echo ">>> [make test-mp] Headless 1 Host + 2 Clients co-op E2E smoke test"
	@$(PYTHON) .agent/skills/headless-coop-playtester/scripts/run_coop_smoke.py --duration 10

test-perf:
	@echo ">>> [make test-perf] 1,000-tick physics & orphan-node benchmark"
	@$(PYTHON) .agent/skills/clip-telemetry-profiler/scripts/run_profiler.py

verify-all: check test-unit test-mp test-perf
	@echo ""
	@echo "========================================================"
	@echo " [PASS] BODYGUARD INC. — ALL QUALITY GATES VERIFIED"
	@echo "========================================================"
