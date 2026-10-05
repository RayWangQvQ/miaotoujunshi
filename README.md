# Miaotoujunshi (喵头军师)

Jev Chat's "chat co-pilot" idea, rebuilt as two layers: an independently
distributable AI Skill, plus three app entries — Android, Windows and macOS.

The floating ball reads the screen → you confirm the transcript → analysis →
candidate replies → **copy, or verified one-tap fill where supported; never
auto-send**. Android one-tap fill is currently tracked in #29.

## Layout

| Layer | Location | What it is |
| --- | --- | --- |
| Upstream payload | `goutoujunshi/` | The `goutoujunshi` / 狗头军师 payload — `SKILL.md`, `references/`, `agents/`, `assets/`, `scripts/`. A maintained fork of the upstream skill, kept byte-identical; `scripts/check_upstream.py` reports the drift |
| Own payload | `miaotoujunshi/` | This repository's own payload: the shared tone rules (`references/knowledge/`), the structured data (`references/data/`) and the demo cases (`examples/`) all three ports read at runtime. See `docs/adr/0006` |
| Apps | `integrations/jev_flutter` | One Flutter app for the promoted Android, macOS and Windows ports |
| Repo tooling | `scripts/` | `validate_layout.py` (root-entry allowlist), `check_upstream.py` (upstream drift) |

Every entry at the repository root is registered with the layer it belongs to in
`scripts/validate_layout.py`; an unregistered entry fails the build. The app layer
has three registered root-level exceptions — `tests/`, `documentation/` and
`PRIVACY.md` — each with its reason recorded there.

The repository deliberately carries `miaotoujunshi` / 喵头军师 at three places — the
app display name, the technical identifier prefix and the own-payload directory —
while the upstream Skill layer stays `goutoujunshi` / 狗头军师 and the floating-ball
UI element is 「喵球」. **They are layered on purpose — do not mix them.** See
[GLOSSARY.md](GLOSSARY.md).

## Origin, attribution and licensing

The Flutter application contains derivative logic from the upstream Jev Chat
assistants. Its translated attribution, including the retained Android capture
and adapter logic, is recorded in the root `NOTICE`.

The root and the promoted Android, Windows and macOS preview artifacts are MIT.
Their third-party notices remain in `NOTICE`, but no release artifact carries a
repository-wide copyleft constraint.

The full provenance table, the attribution obligations and the licence split
live in [NOTICE](NOTICE); privacy notes in [PRIVACY.md](PRIVACY.md).

## Validation

```bash
python -B -m unittest discover -s tests
python -B scripts/validate_layout.py
python -B goutoujunshi/scripts/validate_skill.py --runtime
python -B scripts/check_upstream.py    # network required; read-only drift report
```

> `validate_skill.py` ships inside the payload directory, so it needs `--runtime`:
> without it the script demands the repository-level `README.md` and `LICENSE` in
> its own root, which is now `goutoujunshi/`.
>
> Do not run `compileall` over the repository: the `__pycache__` it produces makes
> `validate_skill.py` fail, and has to be cleaned up by hand.
