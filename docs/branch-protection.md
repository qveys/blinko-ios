# Branch Protection

`main` is the release branch. It should only ever move through a reviewed pull
request. This document records the intended configuration, how to apply it, and
how to verify it took effect.

## Currently deployed

`main` **is protected**, applied by the repo admin as a **repository ruleset**
(`main`, id `20595357`) rather than via the classic branch-protection API. A
direct push is rejected — verified behaviourally, not just by reading the API.

The live ruleset differs from the spec below in three ways worth knowing:

| | Spec below | Live ruleset |
|---|---|---|
| Required approving reviews | 1 | **1** |
| Require linear history | off | **on** — no merge commits; PRs must squash or rebase |
| Require signed commits | not specified | **on** |
| Required status check | `Build and Test` | **`check`** |

The signing and linear-history rules have a practical consequence: a locally
made merge commit cannot land. Unsigned commits are fine on feature branches —
the ruleset only targets `main` — and GitHub signs the commit it creates when a
PR is merged, so the normal PR flow satisfies `required_signatures` with no
agent-side signing setup. See `docs/commit-signing.md`, which also records why
local SSH/GPG signing cannot be made to verify here.

The required-check context is currently `check`, but the workflow reports
`Build and Test`. PRs with a green build are still blocked because the required
context never appears. Edit **Settings → Rules → Rulesets → main** and change the
required status check from `check` to `Build and Test`.

## Intended configuration for `main`

| Setting | Value | Why |
|---|---|---|
| Require a pull request before merging | on | No direct pushes to `main`. |
| Required approving reviews | 1 | Every change gets a second pair of eyes. |
| Dismiss stale approvals on new commits | on | An approval covers the diff it was given for, not whatever lands afterwards. |
| Require conversation resolution | on | Review comments get answered, not merged past. |
| Include administrators (`enforce_admins`) | on | The rule is worthless if the people most able to break `main` are exempt. |
| Block force pushes | on | `main` history stays append-only and bisectable. |
| Block branch deletion | on | Guards against tooling accidents. |
| Require linear history | off | Merge commits from PRs are fine and keep the branch topology honest. |
| Require status checks | `Build and Test`, once CI is on `main` | Auto-detected — see below. |

Status checks are applied **conditionally**. The script looks for
`.github/workflows/ios-ci.yml` on the target branch:

- **Present** → requires the `Build and Test` check, with `strict: true` so a
  branch must be up to date with `main` before merging.
- **Absent** → applies protection with no required checks, and says so.

This is gated rather than hardcoded because requiring a check that no workflow
ever reports leaves every PR stuck on "Expected — waiting for status", with no
way to merge. The CI pipeline lands in
[PR #3](https://github.com/qveys/blinko-ios/pull/3); **re-run the script after
that merges** to add the gate.

Note the required context is the job's `name:` (`Build and Test`), not its YAML
key (`build-and-test`). Using the key silently never matches.

## Applying it

Requires **admin** on the repository — a `maintain` role is not sufficient for
the branch-protection endpoint. Run either of these as an admin:

```bash
./scripts/apply-branch-protection.sh
```

or configure it by hand: **Settings → Branches → Add branch protection rule**,
pattern `main`, then tick the boxes in the table above.

### If you are automating this with the Paperclip bot

The `my-paperclip-company` GitHub App is installed on this repository but does
not hold the `administration: write` permission, so it receives
`403 Resource not accessible by integration` on both the branch-protection and
rulesets endpoints. To let it self-serve:

**Settings → GitHub Apps → `my-paperclip-company` → Permissions → Administration: Read & write**,
then approve the permission-change request GitHub emails to the repo admin.
Adding the bot as a `maintain` collaborator does *not* grant this.

## Verifying

```bash
gh api repos/qveys/blinko-ios/branches/main/protection \
  --jq '{
    reviews: .required_pull_request_reviews.required_approving_review_count,
    dismiss_stale: .required_pull_request_reviews.dismiss_stale_reviews,
    admins: .enforce_admins.enabled,
    force_push: .allow_force_pushes.enabled,
    deletions: .allow_deletions.enabled,
    conversations: .required_conversation_resolution.enabled,
    checks: [.required_status_checks.checks[]?.context]
  }'
```

Expected (`checks` is `[]` until the CI pipeline merges, then `["Build and Test"]`):

```json
{
  "reviews": 1,
  "dismiss_stale": true,
  "admins": true,
  "force_push": false,
  "deletions": false,
  "conversations": true,
  "checks": ["Build and Test"]
}
```

A `404 Branch not protected` means the rule is not applied. Note that
`GET .../protection` itself requires admin — a non-admin token gets `403` even
when protection *is* configured, so 403 and 404 mean different things here.

The end-to-end check is behavioural: from an up-to-date clone, `git commit`
directly on `main` and `git push origin main`. With protection active the push
is rejected with `GH006: Protected branch update failed`. If it succeeds, the
rule is not in force regardless of what the UI shows.

Note that the checks above read the *classic* branch-protection API. Protection
applied as a **ruleset** shows up there too, but the authoritative view is
`gh api repos/qveys/blinko-ios/rulesets` and
`gh api repos/qveys/blinko-ios/rulesets/{id}`. If the classic endpoint looks
empty, check rulesets before concluding nothing is configured — and either way,
trust the push test over both.

## PR requirements in this repo

Protection is the server-side half. The repo-side half lives in `.github/`:

- `.github/pull_request_template.md` — the checklist every PR opens with.
- `.github/CODEOWNERS` — routes review requests by path. These become *required*
  reviewers only if "Require review from Code Owners" is also enabled on the
  protection rule.

Branch naming and commit-message conventions are in `docs/git-workflow.md` and
`docs/pr-conventions.md`.
