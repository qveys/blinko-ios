# BLI-29 — Blinko-parity tag UX for iOS

## Source web behavior to mirror

Evidence from upstream Blinko web:

- `app/src/components/Common/PopoverFloat/tagSelectPop.tsx`: while editing a note, typing a hashtag opens an anchored tag picker. It filters existing path tags by the typed text after `#`, supports arrow-key selection and Enter/click insertion, inserts `#<tag>`, and shows `no-tag-found` when no existing tag matches.
- `app/src/components/Common/TagListPanel.tsx`: tags appear as a hierarchical sidebar tree. Selecting a tag updates the note-list filter to that tag, highlights the selected row with primary color, and navigates to the all-notes route with `tagId`. Parent tags show expand/collapse affordances and child counts.
- Blinko API contract note: note content is the source of truth for tags. The client does not maintain a separate per-note tag assignment list; Blinko parses `#tag` tokens from note markdown on write. Nested tags are segment rows, so `#work/projects` is a path-style tag, not a separate mobile taxonomy.

## iOS principles

- Match Blinko web semantics first: tags are inline markdown hashtags plus a list filter, not a separate organizer.
- Do not introduce tag-management screens, taxonomy CRUD, destructive tag delete, rename, icon picking, or AI emoji actions in this scope.
- Reuse normal iOS surfaces for mobile fit: inline suggestions near the caret when feasible; otherwise a compact bottom sheet/popover anchored from the editor.
- Preserve Blinko visual language: hashtag icon, primary selected state, rounded hover/selected equivalents, compact chip-like rows.

## Note display on cards and detail

- Render note tags as compact chips derived from parsed note tags, not as editable taxonomy objects.
- Chip anatomy: leading `#`, full path label when short, leaf label plus accessible full path when long, rounded capsule background, primary/secondary text matching the current color scheme.
- On note cards, show one line of chips below the note excerpt. If overflow occurs, truncate after available width and show `+N`.
- On note detail, show all chips in a wrapping row near note metadata or below title/content preview.
- Tapping a chip from a read-only card/detail applies that tag as a note-list filter.

## Note editor: add an existing tag

### Trigger

- When the user types `#` followed by zero or more non-space characters, show an existing-tag suggestion surface.
- Search text is the active token with `#` removed.
- Suggestions filter existing path tags case-insensitively by substring, matching web behavior.
- If the user types a nested path such as `#work/`, continue filtering path tags against the full typed path after `#`.

### Suggestion surface

- Present a compact list titled only by context, not a full management panel.
- Row anatomy:
  - leading hashtag icon or tag icon if already supplied by API
  - `#tag` or `#parent/child` display label
  - optional subdued parent/path metadata only if required to disambiguate duplicate leaf names
- Use 44 pt minimum row height, 16 pt horizontal padding, 8-12 pt corner radius.
- Highlight the focused/pressed row with the app primary tint and selected text color, mirroring web's selected primary row.
- Limit visible rows to about 5 on compact phones; scroll within the surface.

### Selection

- Tap a row to replace the active hashtag token with `#selected/path` followed by a trailing space.
- Hardware keyboard: Up/Down moves focus cyclically; Return inserts the focused tag; Escape/dismiss hides suggestions.
- After insertion, keep focus in the editor.
- The server becomes authoritative after save because tags are parsed from note content.

### Zero tags / no matches

- If the account has zero tags, do not show an empty picker on `#`; allow free typing of a new hashtag in content.
- If tags exist but none match the typed text, show a single disabled row: `No tag found`.
- Do not offer `Create tag`, `Manage tags`, or taxonomy setup in BLI-29.

## Note editor: remove a tag from a note

- Tags assigned to a note are represented by inline hashtag text in the note body.
- To remove a tag, the user deletes the hashtag token from the editor content.
- If note detail/list renders tag chips, chip delete may be offered only as an editor shortcut: tapping remove deletes the corresponding inline hashtag token from content, then saves the edited note. It must not call tag-delete endpoints.
- If the same hashtag appears multiple times, remove only the chip/token instance the user acted on or ask through editor selection; do not silently remove all duplicates.

## Note list: select a tag filter

### Entry point

- Use a tag list/filter surface reachable from the note list, matching the web sidebar concept in mobile form.
- Preferred placement: toolbar filter button or horizontal `Tags` affordance near the list controls. It opens a sheet containing the existing tag tree.
- The sheet is a filter picker, not a management view.

### Tag tree behavior

- Display root tags and nested children using indentation.
- Parent rows show expand/collapse chevron and child count, consistent with web.
- Row anatomy: leading hashtag/icon, label, optional child count, optional chevron.
- Tapping a tag selects it as the active note-list filter and dismisses the sheet on compact iPhone.
- The selected tag row uses primary background/tint and selected foreground, matching web selected sidebar item behavior.
- Preserve hierarchy order from API/service; do not invent grouping or categories.

### Active filter state

- On the note list, show the active filter as a removable chip: `#tag/path` plus clear affordance.
- The navigation/list title may remain `Blinko`; avoid creating a separate Tags destination.
- Refresh and pagination operate under the selected tag filter.

## Clear a tag filter

- Tapping the active filter chip's clear affordance clears `tagId` and returns to all notes.
- The tag picker should also include an `All notes` row at the top when opened with a tag selected.
- Clearing does not alter note content or tag records.

## Loading states

- While tags load for editor suggestions, keep typing responsive and show a small inline spinner only if the suggestion surface is already open.
- While the tag filter sheet loads, show skeleton rows or a centered spinner under the sheet title.
- If tag loading fails, show `Couldn't load tags` with a retry action. Do not block all-notes browsing.

## Empty states

### Zero tags available

- In the tag filter sheet: `No tags yet` with supporting text `Tags appear after notes contain hashtags.`
- In the editor suggestion flow: no blocking state; let the user type `#tag` naturally.

### Zero matching notes for selected tag

- Show a note-list empty state specific to filtering: title `No notes with #tag/path`; description `Clear the tag filter or add this hashtag to a note.`
- Primary action: `Clear filter`.
- Secondary action, if note creation is in scope for the screen: compose a note with the tag prefilled only if that matches the existing compose architecture; otherwise omit.

## Accessibility and interaction details

- VoiceOver labels:
  - suggestion row: `Tag, <path>`
  - selected filter chip: `Filtered by tag <path>, clear filter`
  - tree parent row: `<name>, <n> child tags, expanded/collapsed`
- Dynamic Type: rows wrap or truncate path labels at one line in dense pickers; full path available via accessibility label.
- Touch targets: 44x44 pt minimum.
- Haptics: light selection feedback when choosing/clearing a filter; no haptics while simply typing.

## Out of scope / must not add

- Dedicated tag management tab or settings area.
- Rename, delete, sort, move, icon picker, AI emoji, or destructive `delete-tag-with-notes` UI.
- Client-side tag assignment tables separate from markdown content.
- A new taxonomy model divergent from Blinko path tags.

## Engineering handoff checklist

- Reuse `TagService` and flattened/path tag helpers for suggestions and filter rows.
- Persist note tags by editing note markdown content and calling note upsert; do not add a tag-assignment endpoint.
- Filtering should pass the selected `tagId`/server-supported filter in the existing note list request path.
- Safe tag deletion endpoint remains irrelevant to this scope; destructive deletion must remain unreachable.
