# HockeyQuant — iOS (native SwiftUI)

Native iOS client for HockeyQuant. Reuses the existing FastAPI backend
(`../backend`, deployed to Render) and the shared Supabase project for auth.
Prediction math stays server-side — this app is purely a client.

See the migration plan at
`~/.claude/plans/hockeyquant-native-ios-effervescent-fog.md`.

## Requirements

- Xcode 26+ (Swift 6), iOS 17+ deployment target
- [XcodeGen](https://github.com/yonyz/XcodeGen) — `brew install xcodegen`

## Project generation

The `.xcodeproj` is generated from `project.yml` and is **gitignored**.
Regenerate it any time (and after adding files):

```bash
cd ios
xcodegen generate
```

## Supabase config (required, gitignored)

`HockeyQuant/Core/SupabaseConfig.swift` holds the Supabase URL + **public anon
key** (the same one the web app ships). It's gitignored. Copy the template:

```bash
cp HockeyQuant/Core/SupabaseConfig.example.swift HockeyQuant/Core/SupabaseConfig.swift
# then fill in url + anonKey
```

> Never put the Supabase **service** key (or any provider key) in the app — those
> stay server-side. See the plan's "Secrets exposure" note.

## Resolving Swift packages (one-time gotcha)

This machine has `git config --global safe.bareRepository explicit`, which blocks
SwiftPM from reading its bare package repos. Resolve packages with a scoped
override (no global change):

```bash
cd ios
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all \
  xcodebuild -resolvePackageDependencies \
    -project HockeyQuant.xcodeproj -scheme HockeyQuant \
    -derivedDataPath ./DerivedData
```

After resolution the checkouts are cached and normal builds work offline.

## Build & run (simulator)

```bash
xcodebuild -project HockeyQuant.xcodeproj -scheme HockeyQuant \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  -derivedDataPath ./DerivedData build
```

…or drive the simulator via the XcodeBuildMCP tooling (preferred during dev).

## Structure

```
HockeyQuant/
  App/            # @main entry + RootView (5-tab IA)
  DesignSystem/   # Theme tokens + reusable components (build before screens)
  Networking/     # APIClient, Codable models (mirror backend), Logging
  Core/           # TeamInfo, AuthStore (Supabase), SupabaseConfig (gitignored)
  Features/
    Today/        # live predictions feed (the hero screen)
    Profile/      # auth (sign in / sign up) + account
  Resources/      # Assets.xcassets (AppIcon, AccentColor)
```

## Dependencies

- [supabase-swift](https://github.com/supabase/supabase-swift) `2.x` — auth + data

## Backend

Defaults to production (`https://hockeyquant.onrender.com`). Switch to a local
FastAPI server by constructing `APIClient(environment: .local)`.
Note: Render free tier cold-starts (30–60s); the app pre-warms `/health` and
shows a loading state.
