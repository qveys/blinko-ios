# Blinko iOS Client Roadmap

**Goal**: Build a faithful native iOS client for Blinko that delivers core functionality with high fidelity to the web experience.

**Project**: blinko-ios-client (BLI)

---

## Phase 1: Foundation (Q3 2026)

**Milestone 1.1: Project Setup & Architecture**
- [ ] BLI-7: Initialize iOS project with SwiftUI + modern architecture
- [ ] BLI-8: Set up CI/CD pipeline (GitHub Actions, fastlane)
- [ ] BLI-9: Define data models and API contracts from Blinko backend
- [ ] BLI-10: Implement authentication flow (login, token management)

**Milestone 1.2: Core Navigation & Home**
- [ ] BLI-11: Build tab navigation structure (Home, Notes, Search, Settings)
- [ ] BLI-12: Implement note list view with infinite scroll
- [ ] BLI-13: Create note detail view with markdown rendering
- [ ] BLI-14: Add pull-to-refresh and offline caching strategy

---

## Phase 2: Core Features (Q4 2026)

**Milestone 2.1: Note Creation & Editing**
- [ ] BLI-15: Implement note creation flow (compose, save, sync)
- [ ] BLI-16: Build rich text editor with markdown shortcuts
- [ ] BLI-17: Add tag management UI (create, assign, filter)
- [ ] BLI-18: Implement search with full-text indexing

**Milestone 2.2: Media & Attachments**
- [ ] BLI-19: Add image attachment support (camera, photo library)
- [ ] BLI-20: Implement file upload with progress indicators
- [ ] BLI-21: Build media gallery view for note attachments

---

## Phase 3: Polish & Advanced (Q1 2027)

**Milestone 3.1: UX Refinement**
- [ ] BLI-22: Implement dark mode with system integration
- [ ] BLI-23: Add haptic feedback and micro-interactions
- [ ] BLI-24: Optimize performance for large note collections
- [ ] BLI-25: Implement accessibility features (VoiceOver, Dynamic Type)

**Milestone 3.2: Advanced Features**
- [ ] BLI-26: Build folder/organization system
- [ ] BLI-27: Add note sharing and collaboration UI
- [ ] BLI-28: Implement push notification support
- [ ] BLI-29: Add export functionality (PDF, markdown)

---

## Non-Functional Requirements

**Performance**
- App launch < 2 seconds
- Note list scroll 60fps on 10k+ notes
- Offline support with conflict resolution

**Quality**
- 80%+ test coverage for business logic
- Zero critical crashes in production
- App Store rating target: 4.5+

**Security**
- End-to-end encryption for note content
- Biometric authentication support
- Secure token storage (Keychain)

---

## Dependencies & Risks

**External Dependencies**
- Blinko backend API stability
- SwiftUI framework maturity for target features
- App Store review timeline

**Risk Mitigation**
- API contract versioning to handle backend changes
- Feature flags for gradual rollout
- Beta testing program with power users

---

## Success Metrics

**Adoption**
- 10k+ active users in first 6 months
- 30% of web users adopt iOS client

**Engagement**
- Average session duration > 5 minutes
- Daily active users > 40% of monthly active users

**Quality**
- Crash rate < 0.1%
- Support ticket volume < 2% of active users

---

*Roadmap last updated: 2026-08-09*
*Next review: End of Phase 1*