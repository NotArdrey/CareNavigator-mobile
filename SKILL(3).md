---
name: carenavigator-fresh-system-builder
description: >
  Use to build CareNavigator PH as a completely new Flutter mobile/web system
  from the documented architecture, product requirements, Supabase contracts,
  and professional visual reference. Creates a fresh implementation rather than
  preserving or refactoring the old frontend. Requires GoRouter, Riverpod,
  repositories, Supabase Auth/Postgres/RLS/Realtime/Storage/Edge Functions,
  existing environment contracts, live Supabase MCP verification, full action
  wiring, accessible overlays, role-aware workflows, and mobile/web validation.
argument-hint: "[feature, role, route, or full system]"
user-invocable: true
license: MIT
metadata:
  version: "3.0.0"
  project: "CareNavigator PH"
---

# CareNavigator PH Fresh System Builder

Build a completely fresh system.

Do not preserve, migrate, imitate, or refactor the current frontend UI, widgets, layouts, themes, design tokens, or responsive implementation.

Read:

1. `MASTER_PROMPT.md`
2. `SYSTEM_ARCHITECTURE.md`
3. `DESIGN_REQUIREMENTS.md`
4. `SUPABASE_SAFETY.md`
5. `VISUAL_REFERENCE.md`
6. `VISUAL_REFERENCE.png`

## Architecture

Use:

- Flutter mobile/web
- GoRouter
- Riverpod
- Dart repositories
- Typed models
- Supabase Auth
- PostgreSQL
- RLS
- Realtime
- Private Storage
- Edge Functions
- Existing external integrations

Do not move privileged logic or secrets into Flutter.

## Environment

Reuse the existing environment-variable names, public client configuration, Supabase project references, `supabase/config.toml`, `--dart-define` values, and Supabase secret storage.

Never expose, rename, duplicate, or hardcode secrets.

## Database

Use Supabase MCP before any schema-dependent work.

Never guess live tables, columns, relationships, policies, functions, or migrations.

## Design

Create an original professional clinical UI.

Use the visual reference as the quality benchmark, not as a pixel-perfect template.

Do not copy its fictional names, data, logos, metrics, or chart values.

Do not use React shadcn/ui in Flutter.

## Scope

Implement every documented role, feature, route, state, action, responsive layout, and overlay.

Do not reduce the work to a static demo.

## Action safety

Verify handlers, routes, IDs, payloads, repositories, providers, loading, disabled, success, errors, confirmation, refresh, Realtime, mobile behavior, and web behavior.

## Overlay safety

All dialogs, alerts, menus, sheets, toasts, date pickers, loading overlays, and floating elements must appear above navigation, maps, media, and WebViews.

Use a root-level Flutter overlay architecture.

## Verification

Run:

- Flutter analysis
- Unit tests
- Widget tests
- Web build
- Android build
- Supabase tests where relevant
- MCP live verification
- Required deployments
- Mobile and web screenshot review

## Completion

Do not claim completion until the fresh system is connected, role-aware, responsive, accessible, tested, deployed where required, and verified against the visual quality benchmark.
