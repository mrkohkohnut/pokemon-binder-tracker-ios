# Poké Binder (iOS)

SwiftUI port of [pokemon-binder-tracker](https://github.com/mrkohkohnut/pokemon-binder-tracker): pick one favourite card printing for each of the 1,025 National Dex Pokémon.

## Run

1. Open `PokeBinder.xcodeproj` in Xcode 16+.
2. Under Signing & Capabilities, choose your team and change the bundle ID from `com.example.PokeBinder` to your own.
3. Run. Requires iOS 17+.

The iCloud key-value storage capability is already set in `PokeBinder.entitlements`. Xcode's automatic signing registers it with your Apple Developer account. If Xcode doesn't list iCloud under Signing & Capabilities, add the capability and tick **Key-value storage**.

## What's ported

- A binder grid of 16 pockets per page, with search, Caught/Missing filter, region filter and card-language filter
- Progress header
- Card station: card catalogue from the live [TCGdex](https://tcgdex.net) API (GraphQL with a REST fallback), grouping of Mega, regional, paired and special forms, catalogue search and filter chips, a manual "unlisted card" option, and a choice of card language

## Differences from the web app

- The collection syncs through iCloud key-value storage, tied to the device's Apple ID, so there's no separate sign-in. It works offline and when signed out of iCloud, then syncs when it can. The web app's Sign in with ChatGPT sync isn't included, because it only works on the web app's hosting platform.
- The Pokémon names in `PokeBinder/PokemonData.swift` are generated from the web app's `app/data/pokemon.ts`.
