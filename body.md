## Summary

```diff
 jobs:
   build-and-test:
-    runs-on: macos-14
+    runs-on: macos-15
```

`docs/CI-CD.md` runner row updated. Scripts pick the simulator via `simctl` (no hardcoded device), so no script change.

## Evidence

- **Before:** "Build and Test" cancelled after 1 s: `The configuration 'macos-14-arm64-us-default' is not supported` (image retired).
  **After:** see the PR's "Build and Test" check on `macos-15`.

## Merge Danger

**Door:** two-way

**Blast Radius:** CI only

Required check on main; unblocks all PRs. Revert restores the old (broken) label.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
