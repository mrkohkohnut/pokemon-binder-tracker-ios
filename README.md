# Poké Binder (iOS)

SwiftUI port of [pokemon-binder-tracker](https://github.com/mrkohkohnut/pokemon-binder-tracker): pick one favourite card printing for each of the 1,025 National Dex Pokémon.

## Run

Open `PokeBinder.xcodeproj` in Xcode 16+, choose your team under Signing & Capabilities, and run. Requires iOS 17+.

## What's ported

- A binder grid of 16 pockets per page, with search, Caught/Missing filter, region filter and card-language filter
- Progress header
- Card station: card catalogue from the live [TCGdex](https://tcgdex.net) API (GraphQL with a REST fallback), grouping of Mega, regional, paired and special forms, catalogue search and filter chips, a manual "unlisted card" option, and a choice of card language

## Differences from the web app

- The collection is saved on the device, in `Documents/binder-collection.json`. The web app's cloud sync relies on Sign in with ChatGPT, which only works on its hosting platform, so it isn't included.
- The Pokémon names in `PokeBinder/PokemonData.swift` are generated from the web app's `app/data/pokemon.ts`.
