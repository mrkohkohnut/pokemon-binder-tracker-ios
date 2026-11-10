# Poké Binder (iOS)

SwiftUI port of [pokemon-binder-tracker](https://github.com/mrkohkohnut/pokemon-binder-tracker): pick one favourite card printing for each of the 1,025 National Dex Pokémon.

## Run

1. Open `PokeBinder.xcodeproj` in Xcode 16+ and build. Requires iOS 17+. No special capabilities are needed, so the app can be re-signed by any signer (FlareStore, etc.).
2. Sync goes through the Mac mini at `https://pokemon.kohkohnut.ing` (see [Sync server](#sync-server)). The web app's `/api/sync` endpoint speaks the same protocol and still works if you enter its address instead.

## Syncing two phones

Local Xcode builds on the Mac mini can sync automatically: each phone joins the same binder on launch. The automated group-release script deliberately omits the shared code, so recipients link manually.

Direct Xcode builds can use `PokeBinder/auto-sync-code.txt`, a shared code that's gitignored because this repo is public. The automated group-release script excludes it. To set it up on a new Mac, create the file with any 20+ letters and digits:

```bash
python3 -c "import secrets; print(''.join(secrets.choice('ABCDEFGHJKLMNPQRSTUVWXYZ23456789') for _ in range(32)))" > PokeBinder/auto-sync-code.txt
```

Anyone who has a direct-Xcode build containing the code could extract it, so only share those builds with people you'd let edit your binder. Releases from `Scripts/release.py` omit the code and fall back to manual sync codes: tap the cloud button, **Start syncing this binder** on one phone, then enter the code on the other.

Changes upload straight away. The other phone picks them up within about 15 seconds while the binder is open, when the app comes back to the foreground, or when you pull down to refresh.

## Sync server

`Server/sync_server.py` is a stdlib-only Python server for `GET`/`PUT /api/sync` (`Authorization: Bearer <sync code>`, body `{"collection": {...}}`). Each sync code is its own binder, saved as `binders/<sha256 of code>.json`.

On the Mac mini it runs from `~/Library/Application Support/PokeBinderSync` on `127.0.0.1:8767`, kept alive by `Server/com.nicholaskoh.pokebinder-sync.plist` (copied to `~/Library/LaunchAgents`). The `anime-sync` Cloudflare tunnel (`~/.cloudflared/anime-sync.yml`) routes `pokemon.kohkohnut.ing` to it. Logs: `~/Library/Logs/PokeBinderSync/sync.log`.

To update the server after editing it:

```bash
cp Server/sync_server.py ~/Library/Application\ Support/PokeBinderSync/ && launchctl kickstart -k gui/$(id -u)/com.nicholaskoh.pokebinder-sync
```

## Releasing

On the Mac mini, run `python3 Scripts/release.py` from a clean worktree. It increments the marketing patch and build number in both Xcode configurations, makes a clean unsigned device build, verifies the IPA, excludes the private auto-sync code, sends the version-labelled IPA to the configured Telegram home chat (currently Fat Fatty Fatter), and commits the version bump. Recipients link phones manually in Sync settings.

Use `python3 Scripts/release.py --dry-run` to preview the next version. The release command does not push to GitHub; push the release commit separately when ready. Xcode and the Hermes CLI with Telegram configured are required. By default it resolves the exact **Fat Fatty Fatter** group from Hermes's Telegram channel directory; set `POKEBINDER_TELEGRAM_TARGET=telegram:<chat-id>` to override it.

## What's ported

- A 4×4 binder grid (16 pockets per page, like the physical binder; two pages side by side on wide screens), with search, Caught/Missing filter, region filter and card-language filter
- Progress header
- Card station: card catalogue from the live [TCGdex](https://tcgdex.net) API (GraphQL with a REST fallback), grouping of Mega, regional, paired and special forms, catalogue search and filter chips, a manual "unlisted card" option, and a choice of card language

## Rarity and the AR goal

- Every card and pocket has a border showing its rarity:
  - **AR** (Illustration Rare / アートレア): rainbow
  - **SAR**: pink to violet
  - **SR, UR, HR and other gold-tier cards**: gold
  - **RR and other double rares**: silver
  - **Common, uncommon and rare**: no special border
- Where the rarity comes from:
  - **English:** TCGdex's rarity names.
  - **Japanese:** the official site's hidden rarity filters (`sc_rare_ar=1`, …).
  - **Chinese:** the official site's `rarity[]` filter.
  - **Korean:** the matching Japanese cards.
- A caught pocket shows where it stands against the goal of having an AR for every Pokémon:
  - the AR chip if your card is an AR;
  - an up arrow if an AR exists in that language to upgrade to;
  - a gold **MAX** crown if no AR exists for that Pokémon in that language, so the card you have is already the best you can get.
- The **AR goal** bar counts these states, and **Need AR** in the status filter lists the pockets you can still upgrade.
- How the AR check works:
  - Each caught Pokémon is checked in its card's language with one small search.
  - The check re-runs weekly, or straight away with **Rescan**.
  - Opening a Pokémon also refreshes the rarity of the card you saved.
- TCG Pocket (phone game) cards are left out of the English catalogue.

## Differences from the web app

- The collection syncs through your own `/api/sync` server (the Mac mini by default) with a sync code, not iCloud or a ChatGPT sign-in. iCloud only works when the app is signed with your own Apple Developer account, so re-signed IPAs (such as FlareStore) can't use it. The phones' binder is stored separately from the binder of the ChatGPT account signed in on the website.
- The Pokémon names in `PokeBinder/PokemonData.swift` are generated from the web app's `app/data/pokemon.ts`.
