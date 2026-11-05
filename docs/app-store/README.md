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

- **Description:** `description.txt` is saved in the 1.1 draft: it adds the Game Boy
  Printer, Game Boy Camera, tilt cartridges, gameplay presets, Automatic hardware, artwork, Plus,
  and the credit for the game in the listing screenshots. The 1.0 text is in this file's history.
- **What's New:** [whats-new/1.1.txt](whats-new/1.1.txt) is saved in the draft. Its lines for the save
  menu and badges, the haptics and the Export Save sizes describe changes made after build 223, so
  the draft needs a newer build before they are true.
- **Plus purchase:** its description and review notes match `plus-purchase.md`. The description
  change is Ready for Review in the same draft submission as the app.
- **Keywords and promotional text:** `listing.md` records the values saved in the 1.1 draft.
- **Screenshots:** ten light-appearance screenshots are placed in numbered order for both
  6.5-inch ([run 41816155374](https://github.com/thisjustin816/press-any/actions/runs/41816155374))
  and 6.9-inch ([run 41816150929](https://github.com/thisjustin816/press-any/actions/runs/41816150929))
  iPhones. Smaller displays use Apple's scaled assets. Both runs captured commit `9461ba6`.
  Gameplay shows Tobu Tobu Girl Deluxe by Tangram Games (CC BY 4.0), credited at the end of the
  description. Capture settings are in [TestFlight](../testflight.md).

The 1.1 draft has build 223 selected and uses manual release. `testflight/223` and
`v1.1.0-beta.1` identify its source commit, `7f85634`. CI and the iOS build passed on that commit.
The original review test-game attachment is processed. The app and Plus metadata are staged
together as two items ready to submit; neither has been submitted to App Store review.

Build 223 is assigned to the Public Beta group and is waiting for Beta App Review. Wait for
external testing and review any reported issues before submitting the App Store candidate.
