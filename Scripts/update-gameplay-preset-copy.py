from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if old not in text:
        raise SystemExit(f"missing replacement anchor in {path}: {old!r}")
    file.write_text(text.replace(old, new, 1))


replace_once(
    "App/AppContainer.swift",
    "    /// Off without Plus, whatever is stored.\n",
    "    /// Stored display filters render for everyone; Settings gates manual Custom editing behind Plus.\n",
)

replace_once(
    "docs/backlog.md",
    "Raw/Accurate/Custom gameplay presets and model-specific display filters",
    "Clean/Accurate/Custom gameplay presets and model-specific display filters",
)

replace_once(
    "docs/mvp-verification.md",
    "- [ ] Choose Raw, confirm Display Filter and Frame Blending are Off and Button Bounce is Off, then reset the preset and confirm inherited values return.",
    "- [ ] Choose Clean, confirm Display Filter and Frame Blending are Off and Button Bounce is Off, then reset the preset and confirm inherited values return.",
)
replace_once(
    "docs/mvp-verification.md",
    "- [ ] Without Plus, choosing Accurate opens Press Any Plus and does not change the stored low-level settings. Raw remains selectable.",
    "- [ ] Without Plus, Clean and Accurate remain selectable and apply their effects. Trying to change a preset-controlled advanced setting opens Press Any Plus and leaves the stored value unchanged.",
)

replace_once(
    "docs/product.md",
    "- **Display filters**: LCD 1×, LCD 3×, CRT 240p and GameCube TV (see Picture).",
    "- **Custom gameplay tuning**: manual control of screen colors, display filters, frame blending and button bounce beyond the free Clean and Accurate presets (see Picture).",
)
replace_once(
    "docs/product.md",
    "From System settings down through Game and Build, **Gameplay Preset** groups the authenticity\nsettings without replacing them. **Raw** removes display filtering, frame blending, display color\ncorrection and button-contact bounce. **Accurate** writes a curated combination for the selected\nModel: handheld models use their matching LCD treatment and screen colors, Super Game Boy models\nuse a restrained consumer 240p CRT treatment, and Game Boy Player uses a cleaner GameCube-era TV\ntreatment. Editing any controlled setting makes the displayed preset **Custom**; returning every\nvalue to a built-in combination recognizes Raw or Accurate again. The preset itself is not stored,\nso existing settings and App -> System -> Game -> Build inheritance keep their behavior.",
    "From System settings down through Game and Build, **Gameplay Preset** groups the authenticity\nsettings without replacing them. **Clean** removes display filtering, frame blending, display color\ncorrection and button-contact bounce. **Accurate** writes a curated combination for the selected\nModel: handheld models use their matching LCD treatment and screen colors, Super Game Boy models\nuse a restrained consumer 240p CRT treatment, and Game Boy Player uses a cleaner GameCube-era TV\ntreatment. Clean and Accurate are free. Manually changing a controlled setting requires Plus and\nmakes the displayed preset **Custom**; returning every value to a built-in combination recognizes\nClean or Accurate again. The preset itself is not stored, so existing settings and App -> System ->\nGame -> Build inheritance keep their behavior.",
)
