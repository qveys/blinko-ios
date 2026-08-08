# Commit Signing for Agents

`main` requires signed commits (ruleset `main`, id `20595357`, rule
`required_signatures`). This document records how automated agents satisfy that
rule, why the obvious approach does not work, and how to verify signing end to
end.

**The short version:** agents do not sign commits. They never need to. Feature
branches accept unsigned commits, and GitHub signs the commit that actually
lands on `main` when the PR is merged. No key management, no secrets, no setup.

## Where the signature rule actually applies

The ruleset targets `~DEFAULT_BRANCH` and `refs/heads/main` — and nothing else.
Every other ref in the repo is unprotected. That distinction is the whole
solution, and it is easy to miss:

| Ref | Unsigned commit allowed? |
|---|---|
| `refs/heads/main` | No — rejected |
| Any feature branch | **Yes** |

So the rule never applies to the commits an agent writes. It applies to the
commit the *merge* creates, and GitHub authors that one itself.

Verified behaviourally, not inferred: a plain unsigned local commit
(`git log --format=%G?` → `N`) pushed to `probe/unsigned-merge` was accepted
without complaint.

## What lands on `main` is signed by GitHub

When a PR is merged through the GitHub UI or API, GitHub creates the resulting
commit server-side and signs it with its own key. This holds for all three merge
methods the ruleset allows:

| Merge commit | Method | Branch commit | Merged commit |
|---|---|---|---|
| `aa59ef6c` | squash | `unsigned` | **`verified=true`**, committer `GitHub` |
| `ec8e899b` | squash | — | **`verified=true`**, committer `GitHub` |
| `78bf2cc5` | merge | — | **`verified=true`**, committer `GitHub` |

`aa59ef6c` is the direct proof: its branch head `3a2ff67b` was
`verified=false, reason=unsigned`, and the commit that reached `main` was
`verified=true, reason=valid`. The signature is applied at merge time.

This is why the normal PR workflow already satisfies `required_signatures` with
no agent-side signing configuration at all.

## Why local signing does not work here

Local SSH signing *works* — it just doesn't get you `verified`. Both halves were
tested rather than assumed:

1. **Signing itself succeeds.** `ssh-keygen` is available. Generating an ed25519
   key and setting `gpg.format=ssh` + `user.signingkey` + `commit.gpgsign=true`
   produces a properly signed commit.
2. **GitHub rejects the signature as unrecognised.** Pushing that commit and
   reading its verification gives `verified=false, reason=unknown_key`.

A signature is only `verified` if the public key is registered to the GitHub
account that authored the commit. That registration is the step that cannot be
completed:

- Agents commit as `my-paperclip-company[bot]`, which has **no signing keys** —
  `GET /users/my-paperclip-company[bot]/ssh_signing_keys` returns `[]`.
- Keys are account-level, and the App token is not a user token. `GET /user`,
  `GET /user/ssh_signing_keys`, and `GET /user/gpg_keys` all return
  **`403 Resource not accessible by integration`**. No App permission changes
  this; the endpoints are out of scope for installation tokens entirely.
- GPG is not installed in the agent environment (no `gpg` binary), so the GPG
  route is doubly closed.

Adding a signing key to a *human* account would not help either: the commit is
authored by the bot, and a key registered to a different account yields
`unknown_key` just the same.

**Do not** spend time on: generating agent keys, adding `commit.gpgsign` to the
global git config, installing GPG, or requesting new GitHub App permissions.
None of these produce a verified commit. The merge-signing path above is the
supported method.

## What agents should do

Nothing beyond the normal workflow:

1. Commit locally as usual. Leave `commit.gpgsign` unset — a local signature is
   not merely unnecessary, it shows up as `unknown_key`, which reads as *worse*
   than unsigned in the UI.
2. Push the feature branch. Unsigned commits are accepted there.
3. Open a PR and merge it through GitHub (UI or `PUT /pulls/{n}/merge`). The
   resulting commit on `main` is signed by GitHub.

Never push directly to `main`, and never build a merge commit locally — a local
merge commit is unsigned *and* breaks `required_linear_history`.

Rewriting a branch through the git trees API also yields signed commits, since
anything authored via the API is signed server-side. That is a heavier
workaround and is **not** needed for the normal PR flow — reach for it only when
a commit must be signed on the branch itself.

## Verifying

Check what actually landed on `main`:

```sh
gh api repos/qveys/blinko-ios/commits/main \
  --jq '.commit.verification | {verified, reason}'
```

Expect `{"verified": true, "reason": "valid"}`.

To confirm the branch/`main` split still holds, check a branch head and its
merged counterpart — the branch commit may be `unsigned` while the merged commit
is `valid`. That is the expected, working state, not a defect.

Trust these API results over the local `git log --show-signature` output, which
only reports whether a signature exists, not whether GitHub recognises it.

## Related

- `docs/branch-protection.md` — the full ruleset on `main` and how to change it.
- `docs/git-workflow.md` — branch naming and commit conventions.
