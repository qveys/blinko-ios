# Blinko iOS Client Roadmap

**Goal**: Build a faithful native iOS client for Blinko that delivers core functionality with high fidelity to the web experience.

**Project**: blinko-ios-client (BLI)

**Company goal**: Build a faithful native iOS client for Blinko

---

## Guiding principles

- **Web-app fidelity first** — UI/UX, IA, and core flows must mirror Blinko web before expansion.
- **Server is source of truth** — self-hosted Blinko REST API; offline is cache/draft, not a fork of truth.
- **Ship foundation before polish** — no App Store strategy yet; working, reviewable client first.
- **Ticket IDs only when created** — roadmap bullets without links are planned, not yet in the backlog.

---

## Foundation already landed

| Issue | Status | Deliverable |
|:------|:-------|:------------|
| [BLI-3](/BLI/issues/BLI-3) | done | Design system / visual language |
| [BLI-4](/BLI/issues/BLI-4) | done | System architecture doc |
| [BLI-7](/BLI/issues/BLI-7) | in_review | Tech stack decisions |
| [BLI-5](/BLI/issues/BLI-5) / [BLI-13](/BLI/issues/BLI-13) | blocked | GitHub repo + admin setup |
| [BLI-2](/BLI/issues/BLI-2) | blocked | Branch protection / PR requirements |

---

## Phase 1: Foundation (Q3 2026) — active

### Milestone 1.1: Project setup & architecture

| Issue | Work |
|:------|:-----|
| [BLI-8](/BLI/issues/BLI-8) | Initialize iOS project (SwiftUI + modern architecture) |
| [BLI-9](/BLI/issues/BLI-9) | CI/CD pipeline (GitHub Actions, fastlane docs) |
| [BLI-10](/BLI/issues/BLI-10) | Blinko API contracts + iOS data models |
| [BLI-11](/BLI/issues/BLI-11) | Authentication flow + Keychain token storage |

**Exit criteria**: App boots on simulator, signs in against a Blinko server, CI builds on PR.

### Milestone 1.2: Core navigation & reading

| Issue / item | Work |
|:-------------|:-----|
| [BLI-12](/BLI/issues/BLI-12) | Tab shell (Home, Notes, Search, Settings) |
| Planned | Note list with pagination / infinite scroll |
| Planned | Note detail with markdown rendering |
| Planned | Pull-to-refresh + offline read cache strategy |

**Exit criteria**: Authenticated user can browse and read notes in a shell that matches Blinko IA.

---

## Phase 2: Core features (Q4 2026)

### Milestone 2.1: Note creation & editing

- Note create / edit / delete with server sync
- Markdown-friendly editor (shortcuts + preview)
- Tag create / assign / filter
- Full-text search against Blinko search API

### Milestone 2.2: Media & attachments

- Image attach from camera / photo library
- File upload with progress
- Attachment gallery on note detail

**Exit criteria**: Parity with Blinko web for create/edit/tag/search/attachments on a self-hosted instance.

---

## Phase 3: Polish & advanced (Q1 2027)

### Milestone 3.1: UX refinement

- Dark mode aligned with Blinko + system appearance
- Haptics / micro-interactions where they aid fidelity
- Performance for large note collections
- Accessibility: VoiceOver, Dynamic Type

### Milestone 3.2: Advanced features

- Folders / organization matching web
- Share flows
- Push notifications (if server supports)
- Export (markdown / PDF)

**Exit criteria**: Production-quality UX bar; advanced features only after core parity is solid.

---

## Non-functional requirements

**Performance**
- Cold launch target < 2s on supported devices
- Smooth scrolling on large note lists
- Offline read + draft support with conflict strategy documented

**Quality**
- Automated tests for business logic (auth, models, sync)
- PR review required; crash-free beta bar before any store path

**Security**
- Credentials/tokens in Keychain only
- No secrets in logs or client config committed to git
- Biometrics as optional unlock later (not Phase 1)

---

## Dependencies & risks

| Risk | Mitigation |
|:-----|:-----------|
| Blinko API undocumented / unstable | [BLI-10](/BLI/issues/BLI-10) inventory + fixtures; spike follow-ups |
| GitHub admin / branch protection blocked | [BLI-5](/BLI/issues/BLI-5), [BLI-13](/BLI/issues/BLI-13), [BLI-2](/BLI/issues/BLI-2) |
| Over-scoping past web parity | PO rejects feature creep; Phase 3 gated on Phase 2 exit |
| SwiftUI gaps (rich editor) | UIKit interop only where required (see tech stack) |

---

## Success metrics (directional)

- Web-fidelity review sign-off from Product Owner on auth + notes CRUD + tags + search
- Crash rate < 0.1% in internal/beta use
- Session usefulness: users can complete read → edit → sync without falling back to web for core paths

---

## Backlog batch (this roadmap cycle)

Created and ready for engineering:

1. [BLI-8](/BLI/issues/BLI-8) — project init (critical path)
2. [BLI-9](/BLI/issues/BLI-9) — CI/CD
3. [BLI-10](/BLI/issues/BLI-10) — API models
4. [BLI-11](/BLI/issues/BLI-11) — auth
5. [BLI-12](/BLI/issues/BLI-12) — tab shell

Next backlog generation (when unassigned todos drop below 3): Milestone 1.2 reading flows (list, detail, offline cache).

---

*Roadmap last updated: 2026-08-09*  
*Owner: Product Owner · Next review: after Milestone 1.1 exit*
