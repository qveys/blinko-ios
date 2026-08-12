# Label Taxonomy

This repository uses a small label taxonomy so issues are searchable by work kind,
codebase area, product scope, and estimated size.

## Backlog Owner Rule

Labels must be set accurately at issue-creation time by the backlog owner. If the
work changes meaningfully, update labels as part of backlog grooming instead of
leaving stale bootstrap/default labels in place.

## Required Taxonomy Groups

Apply labels from these groups when creating or grooming issues:

- `Type:` — what kind of work this is.
- `Area:` — which product or codebase area is affected.
- `Scope:` — whether the work belongs to a named delivery scope, such as MVP.
- `Size:` — the expected implementation or review effort.

## Type Labels

Use `Type:` labels to identify the primary kind of work. Multiple `Type:` labels
are acceptable when they are all meaningful, such as research plus documentation.

- `✨ Type: Feature` — new user-facing capability or product behavior.
- `🐞 Type: Bug` — incorrect or broken behavior.
- `🔧 Type: Chore` — maintenance, cleanup, tooling, or operational work.
- `📚 Type: Documentation` — docs, specs, guides, or repo documentation.
- `🎨 Type: Design` — UX, visual design, interaction design, or design-system work.
- `♻️ Type: Planning` — roadmap, backlog, sequencing, or project planning.
- `🔬 Type: Research` — technical or product investigation before implementation.
- `🧪 Type: Test` — adding, updating, or fixing test coverage.
- `🏗️ Type: Build` — build, packaging, Xcode project, release, or CI workflow changes.

## Area Labels

Use `Area:` labels to describe where the work lives. Apply more than one when a
single issue intentionally spans multiple areas.

- `🧩 Area: App` — app entry, coordinator, service container, or app lifecycle.
- `🧩 Area: Architecture` — system design, technical decisions, or architecture docs.
- `🧩 Area: Auth` — authentication, tokens, session, login, or onboarding credentials.
- `🧩 Area: CI` — workflows, actions, scripts, or continuous integration.
- `🧩 Area: Data & Persistence` — local data, persistence, storage, or cached state.
- `🧩 Area: Design` — design system, visual language, or design artifacts.
- `🧩 Area: Docs` — README, ROADMAP, `docs/`, and other repo-level documentation.
- `🧩 Area: Models` — domain models, decoding, and typed data structures.
- `🧩 Area: Networking` — HTTP client, API DTOs, errors, and request/response plumbing.
- `🧩 Area: Notes` — note list, note detail, note services, and note-related UI/logic.
- `🧩 Area: Onboarding` — first-run setup and onboarding flow.
- `🧩 Area: Product` — product definition, roadmap, backlog, or product operations.
- `🧩 Area: Release` — release process, distribution, signing, and delivery readiness.
- `🧩 Area: Services` — service layer, mocks, fixtures, and non-networking services.
- `🧩 Area: Sync` — sync state, metadata, stall detection, and background refresh.
- `🧩 Area: Tags` — tag models, tag services, tag UI, and filtering.
- `🧩 Area: Tests` — unit tests, fixtures, and test tooling.
- `🧩 Area: UI` — SwiftUI views, layout, assets, and visual presentation.
- `🧩 Area: ViewModels` — presentation state and UI binding logic.

## Scope Labels

Use `Scope:` labels for delivery scope, not for technical area.

- `🚀 Scope: MVP` — required for the initial minimum viable product.

## Size Labels

Use `Size:` labels for rough effort sizing. Size is an estimate, not a promise;
update it when discovery changes the expected effort.

- `📏 Size: S` — small, focused change.
- `📏 Size: M` — moderate change with limited discovery or integration work.
- `📏 Size: L` — large change that spans multiple files, domains, or decisions.

## Examples From BLI-15

- Design system work: `🎨 Type: Design`, `🧩 Area: Design`, `🚀 Scope: MVP`, `📏 Size: M`.
- Architecture docs: `📚 Type: Documentation`, `🧩 Area: Architecture`, `🚀 Scope: MVP`, `📏 Size: L`.
- CI/CD pipeline work: `🔧 Type: Chore`, `🧩 Area: CI`, `🧩 Area: Release`, `📏 Size: L`.
