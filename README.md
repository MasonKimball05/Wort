# Wort

German vocabulary with spaced repetition, on iPhone and Mac, synced through iCloud.

- **Starter decks by level.** Settings ▸ Starter decks: **A1** (412 everyday words) for starting out, **C1** (245 entries) for advanced polish: verbs with fixed prepositions and case, noun-verb phrases, false friends, nouns whose meaning changes with the article (der/das Verdienst), idioms, rarer strong verbs. Each deck is added only when asked, so two devices never import it twice.
- **Six drills per word, scheduled separately:** meaning (DE→EN), recall (EN→DE), article (der/die/das, graded by your pick), plural, preposition & case (verzichten → auf + Akk.), and verb forms (verzeihen → verzieh, hat verziehen). Missing an article doesn't reset what you know about the meaning.
- **Add words four ways:** type one in (Wort looks up the article, plural, meaning, verb forms and an example on Wiktionary; "Bücher" resolves to das Buch, "die See" picks sea over lake), share a word or sentence from any app, "Save to Wort" in [Hop](https://github.com/MasonKimball05/hop)'s ⌘K menu on a `de …`/`en …` translation, or a `wort://add?de=…&en=…` link from a Shortcut.
- **Pronunciation** with the on-device German voice.

Swift 6, SwiftUI, SwiftData + CloudKit. No dependencies, no API keys.

## How it fits together

| Piece | Where | Notes |
|---|---|---|
| Scheduler | `Sources/WortCore/Scheduler.swift` | SM-2 with learning steps. Reviews are an append-only log and a card's state is replayed from it, so two devices reviewing offline merge cleanly. |
| Lookup | `Sources/WortCore/Wiktionary.swift`, `Lookup.swift` | Parses the German section of Wiktionary's REST HTML: the rendered headword line for gender, plural and principal parts; senses for meanings and examples. Only the word is sent. Falls back to a compound's last part, then suffix rules (-ung → die), shown as a guess. |
| Starter decks | `Sources/WortCore/Resources/starter-*.tsv` | Tab-separated, original example sentences. Every noun is cross-checked against Wiktionary (`WORT_VALIDATE=1 WORT_LEVEL=C1 swift test --filter wiktionaryAgrees`). |
| Data | `Sources/WortApp/Models.swift`, `Store.swift` | CloudKit-shaped SwiftData (optional/defaulted fields, no unique constraints). Duplicates from two devices are merged on a stable word key, keeping every review. The iPhone store lives in the App Group. |
| Share extension | `Sources/WortShare` | Writes a small JSON file to the App Group inbox and exits; the app looks the word up next launch. A shared sentence waits on the Add tab for you to tap the word. |

## Build

```bash
swift test --scratch-path ~/Library/Caches/Wort/build   # WortCore: parser, lookup, scheduler, decks, inbox
xcodegen generate                                         # after changing project.yml
open Wort.xcodeproj                                       # run Wort-iOS on the iPhone, Wort-macOS on the Mac
```

Signing is automatic on the paid team. The first iPhone build created the App ID, App Group and `iCloud.com.masonkimball.wort` container. The Mac needs to be registered as a device once (Xcode does it when you press Run, or `xcodebuild … -allowProvisioningUpdates -allowProvisioningDeviceRegistration`). Sync only shows between real devices signed in to iCloud; an unsigned or simulator build uses a local store.

Regenerate the icon with `swift Tools/make-icon.swift`.

Dictionary data from [Wiktionary](https://en.wiktionary.org), CC BY-SA.
