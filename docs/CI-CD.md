# CI/CD

Automated build, test, and repository governance for the Blinko iOS client.

## Pipelines

### Build and test

`.github/workflows/ios-ci.yml` runs on every pull request to `main`, every push
to `main`, and on manual dispatch.

| | |
|---|---|
| Runner | `macos-14` |
| Job name | **Build and Test** (job id `build-and-test`) |
| Steps | build for simulator → run unit tests → upload logs and results |
| Artifacts | `ios-ci-results` (build logs + `.xcresult`), retained 14 days |

The job name is what appears in PR checks and is the string branch protection
needs — see [Branch protection](#branch-protection) below.

### Repository governance

| Workflow | File | Trigger | Purpose |
|---|---|---|---|
| **Triage** | `triage.yml` | PR open/edit/sync; issue open/edit; `/triage` comment | Auto-label by path (`labeler.yml`), normalize titles to conventional-commit style |
| **Sync Labels** | `sync-labels.yml` | Push to `main` touching `labels.yml`, or manual | Create/update GitHub labels from `.github/labels.yml` |
| **Stale** | `stale.yml` | Daily cron + manual | Mark inactive issues/PRs after 60 days (never auto-closes) |

Labels are defined in `.github/labels.yml` (source of truth). Path → area mapping
lives in `.github/labeler.yml`. Type / Priority / Effort labels stay manual
(`sync-labels: false` on the labeler step).

Issue forms live under `.github/ISSUE_TEMPLATE/` (bug report, feature request).
Dependabot (`.github/dependabot.yml`) bumps GitHub Actions weekly and will open
Swift Package Manager updates under `BlinkoApp/` once remote deps exist.

**Not ported** from other repos on purpose:

- **Release packaging** — no App Store / TestFlight automation yet (see [Release automation](#release-automation-fastlane)).
- **npm audit / Node test** — this is a Swift/Xcode project; security surface is different.
- **GitHub Pages** — no privacy/support static site in this repo.

## Local equivalents

CI runs the same scripts you do. There is no CI-only build path, so a green run
locally means a green run on CI (toolchain differences aside).

```bash
./scripts/ci-build.sh    # build for the simulator
./scripts/ci-test.sh     # build + run unit tests
```

Both require macOS with Xcode installed. They fail with an explicit message
rather than a confusing error on other platforms.

Override the defaults with environment variables:

```bash
CONFIGURATION=Release ./scripts/ci-build.sh
DESTINATION='platform=iOS Simulator,name=iPhone 15' ./scripts/ci-test.sh
```

| Variable | Default | Purpose |
|---|---|---|
| `SCHEME` | `BlinkoApp` | Xcode scheme to build |
| `CONFIGURATION` | `Debug` | Build configuration |
| `DESTINATION` | auto-resolved | `xcodebuild` destination |
| `DERIVED_DATA` | `build/DerivedData` | Derived data location |
| `RESULTS_DIR` | `build/ci` | Logs and `.xcresult` output |

Install `xcpretty` (`gem install xcpretty`) for readable output. It is optional;
the scripts fall back to raw `xcodebuild` output and still capture full logs.

### Why the simulator destination is resolved at runtime

`scripts/ci-common.sh` queries `xcrun simctl` and picks the newest available
iOS 17+ runtime, preferring an iPhone, rather than hardcoding a device name.

GitHub updates the Xcode and simulator set on its macOS runner images on its own
schedule. A hardcoded `name=iPhone 15` turns the pipeline red the day that image
changes — a failure that looks like a code regression but isn't. Resolving the
destination dynamically keeps CI red for real reasons only.

## Release automation (fastlane)

Not yet configured. The first pass covers build and test validation only, which
is what the team needs to merge safely today. Release automation carries setup
cost (signing certificates, App Store Connect API keys, provisioning) that
should not block CI landing.

When release work begins, add fastlane with lanes along these lines:

| Lane | Purpose |
|---|---|
| `beta` | Build, sign, and upload to TestFlight |
| `release` | Submit to App Store review |
| `screenshots` | Generate localized App Store screenshots |

Prerequisites when that work starts:

- An App Store Connect API key stored as a **GitHub Actions secret**, never in
  a workflow file or the repo.
- A signing strategy — `fastlane match` with a private certificates repo is the
  usual choice for a team.
- A separate workflow triggered on tags, so release builds stay off the PR path
  and don't slow the merge loop.

`.gitignore` already excludes `fastlane/report.xml`, `fastlane/Preview.html`,
`fastlane/screenshots/`, and `fastlane/test_output/`.

## Secrets

The pipeline uses no secrets. It builds with code signing disabled
(`CODE_SIGNING_ALLOWED=NO`), which is sufficient for simulator builds and unit
tests and keeps the pipeline safe to run on pull requests from forks.

`permissions: contents: read` scopes the token to the minimum the job needs.

When signing becomes necessary, put credentials in GitHub Actions secrets and
reference them via `${{ secrets.NAME }}`. Never commit a certificate, profile,
or API key.

## Branch protection

`main` protection is being set up in BLI-2 (PR #2, still open) with
`required_status_checks: null`, because no CI existed when it was written. That
PR adds `docs/branch-protection.md` and `scripts/apply-branch-protection.sh`.

Once this pipeline has landed on `main`, add the job name to the required
contexts in `scripts/apply-branch-protection.sh` and re-run it:

```
contexts: ["Build and Test"]
```

Until that happens, review approval is the only gate between a red build and
`main`.

## Troubleshooting

**A run failed — where do I look?** Open the failed run, download the
`ios-ci-results` artifact. `build/ci/*.log` has full `xcodebuild` output;
`TestResults.xcresult` opens in Xcode with per-test detail.

**"Scheme BlinkoApp not found."** The shared scheme at
`BlinkoApp.xcodeproj/xcshareddata/xcschemes/BlinkoApp.xcscheme` is missing or
was not committed. Xcode writes new schemes to `xcuserdata/` (gitignored) by
default — mark a scheme **Shared** in *Product → Scheme → Manage Schemes* so CI
and every other clone can see it.

**Tests pass locally but fail on CI.** Compare the `Show toolchain` step against
your local `xcodebuild -version`. Runner images move; local Xcode does not.
