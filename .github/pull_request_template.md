<!--
  Title format: <type>(<scope>): <summary>
  e.g. feat(notes): add swipe-to-archive on the note list
  Lowercase after the colon, no trailing period, under 72 chars.
-->

## What

<!-- What changed, in one or two sentences. -->

## Why

<!-- The problem this solves. Link the issue: BLI-<N> -->

Closes BLI-

## How

<!-- Notable implementation choices, trade-offs, anything a reviewer would
     otherwise have to reverse-engineer from the diff. -->

## Verification

<!-- How you confirmed this works. Not "tests pass" — what you actually ran
     and observed. Screenshots or a screen recording for UI changes. -->

- [ ] Built and ran the app; exercised the affected flow end-to-end
- [ ] Added or updated tests covering the change
- [ ] Screenshots attached (UI changes only)

## Risk

<!-- What could break, and how to back it out. Delete if trivially reversible. -->

---

- [ ] Scoped to one concern — unrelated changes split into separate PRs
- [ ] No secrets, tokens, or credentials in the diff
