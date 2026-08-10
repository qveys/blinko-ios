# Blinko API Contracts

How the iOS client talks to a Blinko server: the endpoints it uses, the shapes on
the wire, how errors come back, and what the backend does *not* give us.

**Status:** derived from Blinko's open-source backend (`prisma/schema.prisma`,
the tRPC routers under `server/routerTrpc/`, and the Express file routes). It is
a client-side contract, not an official spec. A running instance serves the
authoritative merged OpenAPI document at `GET /api/openapi.json` — check there
first when something disagrees with this document.

Code: `Services/BlinkoAPI.swift` (paths), `Services/DTO/` (bodies),
`Services/APIError.swift` (errors), `Services/HTTPClient.swift` (transport).

---

## 1. Shape of the API

Blinko exposes two different families of HTTP routes, and they do not behave the
same way. Most client-visible inconsistency traces back to this split.

| | `/api/v1/*` | `/api/file/*` |
|---|---|---|
| Origin | generated from tRPC by `trpc-to-openapi` | hand-written Express |
| Payloads | JSON in, JSON out | multipart in, JSON out |
| Error body | `{message, code, issues}` | `{error}` or `{message}` |
| Casing | `camelCase` | inconsistent (`Message` is capitalized) |

Two consequences worth internalizing:

**Reads are `POST`.** `note/list` and `note/detail` are `POST` with a JSON body.
This is not a mistake in our client — tRPC queries that take an input object are
mapped onto POST by the generator. Do not "fix" these to GET.

**Base URL is the server origin plus `/api`.** Self-hosted instances default to
port `1111`. `BlinkoAPI.baseURL(forServer:)` does this join; every path constant
is relative to it.

---

## 2. Authentication

`POST /api/v1/user/login` — the only unauthenticated call the client makes.

```jsonc
// request
{ "name": "alice", "password": "hunter2" }

// response
{
  "id": 1, "name": "alice", "nickname": "Alice",
  "token": "eyJhbGciOi...", "role": "superadmin", "loginType": "password",
  "image": ""
}
```

Every other request carries `Authorization: Bearer <token>`.

The token is **long-lived and has no refresh endpoint.** It is a JWT that the
server also persists to `accounts.apiToken`. This shapes the client's whole
auth story:

- There is no silent renewal. A `401` means re-authenticate, full stop —
  `HomeViewModel` surfaces this as `requiresReauthentication` rather than a
  generic alert.
- Users can paste a Personal Access Token from Blinko's web settings instead of
  signing in. It goes to the same store and is indistinguishable downstream.
- Because it does not expire on its own, **storage is the security boundary.**
  It must live in the Keychain. `InMemoryTokenStore` is a placeholder that
  satisfies the protocol for tests and previews — replacing it is BLI-11's job,
  and shipping it would be a real vulnerability.

`POST /api/v1/user/regen-token` invalidates the old token and returns a new one.
That is the only server-side revocation available to us.

---

## 3. Notes

### List — `POST /api/v1/note/list`

The workhorse. Every field has a server default, but the client always sends the
full body so behaviour doesn't drift if those defaults change server-side.

```jsonc
{
  "page": 1, "size": 30,
  "orderBy": "desc",
  "type": -1,              // NoteType raw value; -1 = any
  "tagId": null,
  "searchText": "",
  "isArchived": false,     // null = don't filter
  "isShare": null,
  "isRecycle": false,
  "withoutTag": false, "withFile": false, "withLink": false, "hasTodo": false,
  "isUseAiQuery": false    // routes through vector search; needs AI configured
}
```

Returns a bare JSON **array** of notes — not an envelope, no total count. See
§6 for what that costs us.

`type` is an integer: `0` blinko, `1` note, `2` todo. `-1` is a wildcard meaning
"any", accepted by `list` and `upsert` but never stored. Unknown values decode as
`.blinko` rather than failing the response, matching the server's own
`toNoteTypeEnum` fallback — a future note type must not break an entire page.

### Note payload

```jsonc
{
  "id": 42,
  "content": "# Heading\n\nMarkdown body with #work/projects",
  "type": 1,
  "isArchived": false, "isRecycle": false, "isShare": false,
  "isTop": false, "isReviewed": false,
  "accountId": 1, "sortOrder": 0,
  "createdAt": "2024-05-01T12:00:00.000Z",
  "updatedAt": "2024-05-02T09:30:00.000Z",
  "attachments": [ /* see §5 */ ],
  "tags": [ { "noteId": 42, "tagId": 7, "tag": { /* see §4 */ } } ]
}
```

Two decoding traps, both handled:

- **`tags` is the join table, not tags.** Each element is a `tagsToNote` row with
  the real tag nested one level down. `Note.tagRelations` holds the raw rows;
  `Note.tags` flattens them. Prefer the latter.
- **Content is the source of truth for tags.** Blinko parses `#tag` out of the
  markdown body on write. The client does not maintain the tag list separately;
  editing content reassigns tags server-side.

### Scopes: active vs. archived vs. trashed

`isArchived` on the list request is a tri-state filter: `false` (the default
feed) *excludes* archived notes, `true` returns *only* archived ones, and
`null` disables the filter entirely. The active and archived scopes are
therefore disjoint — a note archived from the default list disappears from it
and shows up under the archived filter, exactly as on Blinko web. `isRecycle`
works the same way, and trashed notes never appear in either scope.

### Ordering: pinned first

Blinko web orders the feed pinned-first (`isTop desc`), then by the requested
`orderBy` on `updatedAt`. The server's list endpoint does this itself; the
client re-applies the same rule locally only when a pin toggle changes a row's
group, rather than refetching the page (`HomeViewModel.togglePin`). The sort
must be stable — within the pinned and unpinned groups the server's recency
order is preserved.

### Write — `POST /api/v1/note/upsert`

One endpoint for create and update: omit `id` to create, pass it to update.
Every other field is optional and omitted fields are left untouched, so partial
updates work (`setTop`, `setArchived` send only what changed). Pin/unpin is
`{"id": n, "isTop": true|false}`; archive/unarchive is
`{"id": n, "isArchived": true|false}` — there are no dedicated tRPC routes for
either, and the response is the full updated note either way.

### Deletion is two-stage

| Call | Effect | Reversible |
|---|---|---|
| `note/batch-trash` | sets `isRecycle = true` | yes, via `batch-update` |
| `note/batch-delete` | row is gone | **no** |
| `note/clear-recycle-bin` | purges all trashed | **no** |

`NoteService.trash` / `.restore` / `.delete` map onto these. The naming is
deliberate: `delete` is destructive and the doc comment says so. UI should route
swipe-to-delete to `trash`.

All three take `{"ids": [1, 2, 3]}` and are batch-only — there is no
single-note delete.

---

## 4. Tags

```jsonc
{ "id": 7, "name": "projects", "icon": "", "parent": 3,
  "accountId": 1, "sortOrder": 0,
  "createdAt": "...", "updatedAt": "..." }
```

**Tags form a tree, stored one row per segment.** `#work/projects` is *two* rows:
`work` with `parent: 0`, and `projects` with `parent: <id of work>`. A row's
`name` is the leaf segment only — never the full path. Rendering a full path
means walking up `parent`; `TagService.groupedByParent()` does one level.
`parent == 0` means root (not `null` — `Tag.isRoot` checks for zero).

Deletion has the same destructive/safe split as notes, and here the names are
genuinely dangerous:

- `tags/delete-only-tag` — removes the tag, **keeps** the notes. This is what
  `TagService.deleteTag` calls and what UI should use.
- `tags/delete-tag-with-notes` — removes the tag **and every note carrying it.**
  Not currently reachable from the client. If it is ever wired up it needs an
  explicit, scary confirmation.

Renaming (`tags/update-name`) takes both the old and new name because the server
rewrites the `#tag` text inside every affected note's content.

---

## 5. Attachments

Upload is `POST /api/file/upload`, `multipart/form-data`, field name `file`.

```jsonc
// response — note the capitalized "Message"
{ "Message": "Success", "status": 200,
  "path": "/api/file/1712345678-photo.png",
  "type": "image/png", "size": 20480 }
```

Quirks, all handled in `AttachmentUploadResponse`:

- `Message` is capitalized. This route is hand-written and does not follow the
  generated routes' casing.
- The response has **no `name`** — it is filled in client-side from the path's
  last component, because `note/upsert` requires one.
- `size` arrives as a JSON number *or* a string, because the column is a SQL
  `Decimal` and drivers serialize it inconsistently. `decodeFlexibleInt64`
  accepts both. Same applies anywhere a `Decimal` surfaces.
- `path` is **server-relative**, not an absolute URL. Resolve with
  `Attachment.url(relativeTo:)`.

Uploading does not attach the file to anything. To attach, upload first, then
`note/upsert` with the returned metadata in `attachments`.

---

## 6. Errors and retries

### Envelope

Generated routes return a **flat** object (not tRPC's nested `{error: {...}}`):

```jsonc
{ "message": "UNAUTHORIZED", "code": "UNAUTHORIZED",
  "issues": [ { "message": "Required", "path": ["content"] } ] }
```

File routes return `{"error": "..."}` instead. `APIErrorBody` decodes all three
spellings so a caller always gets a usable message. `issues` is Zod validation
detail, present only on input failures; `path` mixes strings and array indices
and is normalized to `[String]`.

### Status → `APIError`

| Status | Case | Retryable |
|---|---|---|
| 400 | `.badRequest` | no |
| 401 | `.unauthorized` | no — re-auth |
| 403 | `.forbidden` | no |
| 404 | `.notFound` | no |
| 408, 429 | `.server` | **yes** |
| 5xx | `.server` | **yes** |
| transport | `.transport` | **yes** |
| decoding | `.decoding` | no |
| cancelled | `.cancelled` | no |

### Retry policy

Default: **2 retries** after the first attempt, exponential backoff from 500 ms,
doubling, capped at 4 s. `RetryPolicy.none` disables it.

Only `isRetryable` errors retry. The 4xx exclusions matter — retrying a `400`
just burns battery, and retrying a `401` can trip account lockout.

**Retries are not idempotency.** Blinko has no idempotency keys, and `upsert`
without an `id` creates a row. A retried create that actually succeeded but whose
response was lost will duplicate the note. Retrying 5xx on writes is a deliberate
trade — 5xx usually means the write never landed — but any future offline queue
must dedupe on its own; it cannot lean on the server. Flagging this now because
it will bite BLI-13 (offline sync).

`.cancelled` is modelled separately so a cancelled task is never shown as an
error alert.

---

## 7. Sync: what the backend does not offer

**There is no delta endpoint.** No `/changes`, no cursor, no ETag, no
`If-Modified-Since`, no push. `note/list` is offset-paginated and returns whole
rows.

So "sync" in this client means, and can only mean:

- Offset pagination by `page`/`size` (1-based, default size 30).
- End-of-list inferred from a **short page** — fewer than `size` items means no
  more. There is no total count to compare against.
- `SyncMetadata.latestUpdatedAt` tracks the newest `updatedAt` seen, as a
  staleness heuristic for cached lists.

`SyncMetadata` is explicitly **client-side bookkeeping, not a server contract.**

The costs, to be honest about them upfront:

- **Refresh is a full re-fetch.** Pull-to-refresh re-requests page 1; anything
  changed deeper in the list is missed until scrolled.
- **Deletions are invisible.** A note deleted server-side stays in a cached list
  until that page is re-fetched. Nothing tells us it went away.
- **Offset pagination drifts.** A note created while paging shifts every
  subsequent page by one, which can duplicate or skip an item at page edges.

Anything stronger needs `updatedAt` polling built on top. That is BLI-13's
problem, and these three limits are its real constraints.

---

## 8. Open questions

Worth confirming against a live instance before building on them:

1. **Rate limiting** — no documented limits. If the server does throttle, we
   should honour `Retry-After` on `429` rather than our fixed backoff.
2. **Max upload size** — enforced by the reverse proxy in most deployments, so
   it varies per install and cannot be hardcoded. Client should read the failure
   rather than pre-validate.
3. **Version skew** — `v1/public/server-version` is unauthenticated and exists;
   we do not yet check it. Worth a minimum-version gate once contracts firm up.
4. **`isUseAiQuery`** — requires AI configured server-side. Behaviour when it
   isn't (silent fallback vs. error) is unverified; keep it off until tested.
5. **Note history** — `note/history` exists but its payload is unexamined.

---

## 9. Conventions for adding endpoints

1. Add the path to `BlinkoAPI` under the right family.
2. Add DTOs to `Services/DTO/`. Give every field a default matching the
   server's, and prefer `decodeIfPresent` with a fallback over a hard `decode`
   for anything not guaranteed present — one missing optional should not fail a
   whole page.
3. Add a fixture to `Tests/BlinkoAppTests/Fixtures/` and a decode test. Fixtures
   are real response shapes; keep them that way.
4. Note anything surprising here, with the reason. The quirks in §5 cost more
   time to rediscover than to write down.

### Dates

Timestamps are Postgres `Timestamptz(6)`, serialized ISO-8601 **with fractional
seconds** — except values landing exactly on a second, which arrive without
them. `ISO8601DateFormatter` cannot accept both with one option set, so
`JSONDecoder.blinko` tries the fractional formatter and falls back to the plain
one. Use `JSONDecoder.blinko` / `JSONEncoder.blinko` everywhere; a stock
`JSONDecoder` **will** intermittently fail on real data.
