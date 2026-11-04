# Poké Binder (iOS)

SwiftUI port of [pokemon-binder-tracker](https://github.com/mrkohkohnut/pokemon-binder-tracker): pick one favourite card printing for each of the 1,025 National Dex Pokémon.

## Run

1. Open `PokeBinder.xcodeproj` in Xcode 16+ and build. Requires iOS 17+. No special capabilities are needed, so the app can be re-signed by any signer (FlareStore, etc.).
2. Deploy the web app ([pokemon-binder-tracker](https://github.com/mrkohkohnut/pokemon-binder-tracker)) with its `/api/sync` endpoint, as a **public** site.

## Syncing two phones

1. On the phone with your cards, tap the cloud button (top left), enter the web app's `https://` address, then tap **Start syncing this binder**.
2. On the other phone, enter the same address and the sync code, then tap **Link this phone**.

Changes upload straight away. The other phone picks them up within about 15 seconds while the binder is open, when the app comes back to the foreground, or when you pull down to refresh.

## What's ported

- A binder grid of 16 pockets per page, with search, Caught/Missing filter, region filter and card-language filter
- Progress header
- Card station: card catalogue from the live [TCGdex](https://tcgdex.net) API (GraphQL with a REST fallback), grouping of Mega, regional, paired and special forms, catalogue search and filter chips, a manual "unlisted card" option, and a choice of card language

## Differences from the web app

- The collection syncs through the web app's `/api/sync` endpoint with a sync code, not iCloud or a ChatGPT sign-in. iCloud only works when the app is signed with your own Apple Developer account, so re-signed IPAs (such as FlareStore) can't use it. The phones' binder is stored separately from the binder of the ChatGPT account signed in on the website.
- The Pokémon names in `PokeBinder/PokemonData.swift` are generated from the web app's `app/data/pokemon.ts`.
