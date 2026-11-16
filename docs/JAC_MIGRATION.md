# Jac application runtime migration

Completed locally on 2026-11-14, on top of the account-isolation and mobile PWA
changes. All first-party application runtime source now uses Jac. This migration
replaces 18 Python implementation modules (2,017 source lines) and two package
markers with native `.jac` modules. No duplicate Python implementations or
embedded `::py::` blocks are retained in the migrated modules.

Jac still uses its Python runtime and Python standard-library interfaces for
HTTP/TLS, SQLite, files, threading, SMTP and subprocesses. Rewriting a module in
Jac does not eliminate those underlying dependencies. The project keeps the
same pinned `jaclang==0.16.7` and `jac-client==0.3.25`; installed packages are not
patched or upgraded for this migration.

## Module inventory

| Area | Native Jac implementation | Responsibility |
|---|---|---|
| Configuration | `app_settings.jac` | Validated settings, local time, DST, reminders and week boundaries |
| Language input | `ai/intents.jac` | Bounded model requests and structured-intent validation |
| Local model transport | `ai/codex_local.jac` | Optional isolated local CLI invocation and response validation |
| Matching and explanations | `ai/matching.jac`, `ai/explanations.jac` | Product evidence, requested variants, computed-fact explanations |
| Real-store orchestration | `planning/visits.jac`, `planning/comparisons.jac` | Concurrent lookups, single/multi-store and delivery comparisons, rechecks |
| Tax estimates | `planning/tax.jac` | Existing basket tax rules and unknown-rate handling |
| Map and retailer APIs | `integrations/providers.jac`, `integrations/retail.jac` | Geoapify/Kroger adapters, response normalization, bounded product queries |
| Historical evidence | `integrations/openprices.jac` | Open Prices store and product evidence |
| HTTP transport | `integrations/http_transport.jac` | Bounded IPv4/IPv6 connections with TLS and proxy behavior preserved |
| Transit and routing I/O | `integrations/transit.jac`, `integrations/itineraries.jac` | GTFS parsing/cache, verified walking links and route lookup orchestration |
| Notification channel | `integrations/channels.jac` | Existing validated SMTP delivery |
| Coverage analysis | `integrations/coverage.jac` | Query collection, matching coverage and report rendering |
| Suggestions and fixtures | `interests/suggest.jac`, `providers/demo_clock.jac` | Purchase-frequency suggestions and test-only demo date rebasing |

The UI, account store, models, graph walkers, business rules and PWA shell were
already Jac and continue using the same module names. Public imports such as
`planning.visits.recommend` are unchanged; the source file behind that import
is now Jac. User database locations, graph schemas, authentication and provider
configuration are unchanged, so no data migration or new API credential is
required. The application still starts with `jac start main.jac --port 8000`.

## Conversion and behavior checks

The migration was checked against the original implementations, including
compiled AST comparisons, existing regression tests and actual HTTP/browser
workflows. Several pinned converter behaviors needed explicit correction:

- Group conditional expressions so both branches retain the original arithmetic
  and nested quiet-hour rules.
- Keep `raise ProviderError(...) from None` in the correct order, preserving
  public error messages and suppressing private provider exception context.
- Preserve dictionary unpacking and normalize relative provider imports.
- Remove a rejected transfer with a dictionary operation, not Jac graph deletion.
- Preserve adjacent formatted strings and Markdown heading text in reports.

One-off conversion adjustments were confined to a disposable tooling process.
The committed Jac sources compile with the unmodified pinned compiler. The
sources use Jac declarations, typed functions, classes and imports directly;
Python files are not executed from inside Jac wrappers.

`tests/test_jac_runtime.jac` adds native tests for these boundaries: runtime
modules really load from `.jac`, production directories contain no `.py`,
quiet-hour and tax expressions retain their meaning, transport errors remain
sanitized, and failed transfer verification removes the provisional link.

## Verification

Validated locally on 2026-11-14:

- 163 native Jac tests and 167 Python regression tests passed.
- All 18 migrated implementations matched their original normalized compiled ASTs.
- The client build, account isolation checks, HTTP shopping/reminder workflow and
  mobile browser/PWA checks passed.
- A clean Docker image served public mobile assets, rejected anonymous shopping
  requests, and completed account registration, login and shopping-list updates.

Run from the repository root in the project environment:

```bash
source .venv/bin/activate
python -m unittest discover -s tests -p 'test_*.py' -v
jac test
jac build main.jac
python scripts/verify_accounts.py
python scripts/verify_e2e.py
```

Browser verification uses the optional Playwright environment:

```bash
python -m pip install -r requirements-browser.txt
python -m playwright install chromium
python scripts/verify_mobile.py
```

These checks use temporary databases, synthetic provider fixtures and (for
email) a local fake SMTP server. They do not establish fresh live retailer or
paid-model API acceptance. Existing provider coverage and availability limits
still apply. The container build uses the same Dockerfile and serves the
account/PWA interface through Caddy; no deployment configuration change is
needed for the language migration.

## Why Python files remain

The remaining Python files are under `tests/` and `scripts/`. The tests are an
independent regression oracle, and the scripts are developer/acceptance tools
for real HTTP requests, external provider probes, browser automation and local
fake services. They enable the Jac import hook with `import jaclang` when they
import application modules; they do not contain an alternative runtime
implementation. New business behavior belongs in Jac. Browser service-worker
JavaScript, Docker and shell deployment files remain in their platform formats.

This document describes the local implementation. GitHub and Render receive
these changes only after the branch is pushed and deployed.
