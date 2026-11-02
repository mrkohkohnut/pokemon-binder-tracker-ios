# Poké Binder (iOS)

SwiftUI port of [pokemon-binder-tracker](https://github.com/mrkohkohnut/pokemon-binder-tracker): pick one favourite card printing for each of the 1,025 National Dex Pokémon.

## Run

1. Open `PokeBinder.xcodeproj` in Xcode 16+.
2. Under Signing & Capabilities, choose your team and change the bundle ID from `com.example.PokeBinder` to your own.
3. In the iCloud capability, replace the container `iCloud.com.example.PokeBinder` with `iCloud.<your bundle ID>` (Xcode creates it in your developer account). Push Notifications and Background Modes → Remote notifications are already declared in `PokeBinder.entitlements` and `PokeBinder-Info.plist`.
4. Run on a device or simulator signed in to iCloud. Requires iOS 17+.

Before releasing, deploy the schema to production in the [CloudKit Console](https://icloud.developer.apple.com/) and set `aps-environment` to `production` for release builds (Xcode does this when archiving).

## What's ported

- A binder grid of 16 pockets per page, with search, Caught/Missing filter, region filter and card-language filter
- Progress header
- Card station: card catalogue from the live [TCGdex](https://tcgdex.net) API (GraphQL with a REST fallback), grouping of Mega, regional, paired and special forms, catalogue search and filter chips, a manual "unlisted card" option, and a choice of card language

## Differences from the web app

- The collection syncs through CloudKit (SwiftData with the private iCloud database), one record per Pokémon, so there's no separate sign-in. It works offline and syncs when it can. The web app's Sign in with ChatGPT sync isn't included, because it only works on the web app's hosting platform.
- The Pokémon names in `PokeBinder/PokemonData.swift` are generated from the web app's `app/data/pokemon.ts`.
