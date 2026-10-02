# Miaotoujunshi (喵头军师)

Jev Chat's "chat co-pilot" idea, rebuilt as two layers: an independently
distributable AI Skill, plus three app entries — Android, Windows and macOS.

The floating ball reads the screen → you confirm the transcript → analysis →
candidate replies → **one-tap fill, never auto-send**.

## Layout

| Layer | Location | What it is |
| --- | --- | --- |
| Skill | `SKILL.md`, `agents/`, `references/`, `examples/` | The `goutoujunshi` / 狗头军师 capability pack, distributable on its own |
| Apps | `integrations/jev_android`, `integrations/jev_windows`, `integrations/jev_mac` | Floating ball + screenshot/OCR + candidate replies |

The repository deliberately carries three names at three layers: the Skill layer
(`goutoujunshi` / 狗头军师), the app layer (`miaotoujunshi` / 喵头军师), and
「喵球」 for the floating-ball UI element itself. **They are layered on purpose —
do not mix them.** See [GLOSSARY.md](GLOSSARY.md).

## Origin, attribution and licensing

The three ports under `integrations/` are derivative works of the upstream Jev
Chat assistant. Each ships its own LICENSE and attribution files; the root
`LICENSE` covers only the code written in this repository.

**Mind the licence split**: the root is MIT, but the `integrations/jev_windows`
release package is **GPLv3 as a whole**, because it bundles
PySide6-Fluent-Widgets (GPLv3).

The full provenance table, the attribution obligations and the licence split
live in [NOTICE](NOTICE); privacy notes in [PRIVACY.md](PRIVACY.md).

## Validation

```bash
python -B -m unittest discover -s tests
python -B scripts/validate_skill.py
```

> Do not run `compileall` over `scripts/`: the `scripts/__pycache__` it produces
> makes `validate_skill.py` fail, and has to be cleaned up by hand.
