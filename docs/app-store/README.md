# App Store Connect content

Everything Press Any shows on the App Store, kept here so a change is reviewed like code and the
current text is always at hand. App Store Connect is the live copy: when a field changes there,
change it here in the same week, and the other way round.

| File | App Store Connect field | Where it is entered |
|---|---|---|
| [listing.md](listing.md) | Name, subtitle, category, age rating, privacy, copyright, URLs, keywords, promotional text | Apps > Press Any > App Information, App Privacy, and the version page |
| [description.txt](description.txt) | Description (up to 4,000 characters) | The version page, App Store Localization |
| [whats-new/](whats-new/) | What's New, one file per version | The version page; the What's New workflow applies a file (see [TestFlight](../testflight.md)) |
| [plus-purchase.md](plus-purchase.md) | Press Any Plus in-app purchase: type, product ID, price, display name, description, review notes | Apps > Press Any > Monetization > In-App Purchases |

Names, the subtitle and trademark rules are also in [NAMING.md](../NAMING.md); the App Store
name, keywords and icon never carry Nintendo trademarks ([product](../product.md)). Listing
screenshots come from the Screenshots workflow ([CI](../ci.md)) and aren't stored here.

## For 1.1

- **Description:** `description.txt` is the 1.0 text as published. It doesn't mention Game Boy
  Printer, Game Boy Camera, tilt cartridges, gameplay presets, Model or artwork, and needs a 1.1
  revision before submission.
- **What's New:** [whats-new/1.1.txt](whats-new/1.1.txt) is ready.
- **Plus purchase:** its description still fits 1.1; its review notes are current.
- **Keywords and promotional text** aren't recorded yet: copy them from App Store Connect into
  `listing.md`.
- **Screenshots:** re-shoot the listing set after #196 (Game Boy Advance extras) is in.
