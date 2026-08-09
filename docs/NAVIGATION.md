# Navigation & Route Identifiers

How the Blinko iOS app is structured for navigation, and the stable
identifiers future screens and deep links must use.

## Shell structure

```
BlinkoApp (@main)
└── RootView                     — auth gate
    ├── OnboardingView           — unauthenticated / unconfigured
    └── MainTabView              — authenticated shell (TabView)
        ├── Home     → HomeView          (own NavigationStack)
        ├── Notes    → PlaceholderView   (own NavigationStack)
        ├── Search   → PlaceholderView   (own NavigationStack)
        └── Settings → SettingsTabView   (own NavigationStack)
```

- `RootView` owns the auth branch: it shows `MainTabView` only when
  `AppCoordinator.isAuthenticated` is true **and** services are built.
  Signing out tears the shell down and returns to onboarding; the next
  sign-in starts on Home.
- Each tab hosts its **own** `NavigationStack`, so per-tab navigation
  state (push depth, scroll position) survives tab switches and never
  leaks across tabs.
- Tab selection lives in `TabSelection` (`ObservableObject`), injected
  by `RootView` as an environment object. Anything that needs to switch
  tabs programmatically — deep links, notifications, buttons on other
  tabs — calls `TabSelection.select(_:)` rather than touching the
  `TabView` directly.

## Route identifiers

Defined in `BlinkoApp/Sources/BlinkoApp/App/BlinkoTab.swift`. These are
a public contract: they will appear in universal links and persisted
navigation state, so **renaming one is a breaking change** (pinned by
`TabNavigationTests.testRouteIDsAreStable`).

| Tab      | `routeID`  | SF Symbol         |
|----------|------------|-------------------|
| Home     | `home`     | `house`           |
| Notes    | `notes`    | `note.text`       |
| Search   | `search`   | `magnifyingglass` |
| Settings | `settings` | `gearshape`       |

Ids are lowercase and matched case-sensitively; unknown ids are ignored
(`BlinkoTab.tab(forRouteID:)` returns `nil`, `TabSelection.select(routeID:)`
returns `false` and keeps the current tab).

## Deep link scheme (reserved, not yet handled)

The URL scheme below is the agreed shape for when deep-link handling
lands. Nothing registers or parses these URLs yet.

```
blinko://tab/<routeID>                 — switch to a top-level tab
blinko://tab/home                      — open Home
blinko://tab/notes/<noteID>            — future: open a note within Notes
blinko://tab/search?q=<query>          — future: pre-filled search
```

Implementation sketch for the future issue: handle `onOpenURL` at
`RootView` level, parse the first path component with
`BlinkoTab.tab(forRouteID:)`, call `TabSelection.select(_:)`, then hand
the remaining path to the tab's own router.

## Adding a screen inside a tab

1. Push destinations onto that tab's `NavigationStack` (value-based
   `navigationDestination(for:)` preferred, so paths stay codable for
   future state restoration).
2. Don't create nested `TabView`s or additional stacks at the shell
   level.
3. If the screen must be reachable from a link, extend that tab's route
   namespace under `blinko://tab/<routeID>/…` and document it here.

## Adding a new tab

1. Add a case to `BlinkoTab` (rawValue = its route id, lowercase).
2. Add it to `BlinkoTab.displayOrder` where it belongs.
3. Add its screen to `MainTabView.destination(for:)`.
4. Update the table above. `TabNavigationTests` will fail until
   `displayOrder` and `allCases` agree.
