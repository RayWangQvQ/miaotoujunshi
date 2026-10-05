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
has two registered root-level exceptions — `documentation/` and `PRIVACY.md` —
each with its reason recorded there.

The repository deliberately carries `miaotoujunshi` / 喵头军师 at three places — the
app display name, the technical identifier prefix and the own-payload directory —
while the upstream Skill layer stays `goutoujunshi` / 狗头军师 and the floating-ball
UI element is 「喵球」. **They are layered on purpose — do not mix them.** See
[GLOSSARY.md](GLOSSARY.md).

## Origin, attribution and licensing

The Flutter application contains derivative logic from the upstream Jev Chat
assistants. The attribution obligations of all three upstreams — including the
retained Android capture and adapter logic — are carried in the root `NOTICE`.

The root and the promoted Android, Windows and macOS preview artifacts are MIT.
Their third-party notices remain in `NOTICE`, but no release artifact carries a
repository-wide copyleft constraint.

The full provenance table, the attribution obligations and the licence split
live in [NOTICE](NOTICE); privacy notes in [PRIVACY.md](PRIVACY.md).

## Validation

```bash
python -B scripts/validate_layout.py
python -B scripts/validate_attribution.py
python -B goutoujunshi/scripts/validate_skill.py --runtime
python -B scripts/check_upstream.py    # network required; read-only drift report
```

`validate_attribution.py` keeps the licensing notes honest: the three upstreams'
copyright holders and obligations must stay in `NOTICE`, every dependency the
Flutter workspace declares — including its build and test plugins — must be
recorded there with its licence, and `PRIVACY.md` must state the memory-store
bounds the code enforces.

The application's own suite — every package's tests plus the widget tests — lives
in the Flutter workspace and needs Flutter 3.47 or newer; see
[`integrations/jev_flutter/README.md`](integrations/jev_flutter/README.md).

> `validate_skill.py` ships inside the payload directory, so it needs `--runtime`:
> without it the script demands the repository-level `README.md` and `LICENSE` in
> its own root, which is now `goutoujunshi/`.
>
> Do not run `compileall` over the repository: the `__pycache__` it produces makes
> `validate_skill.py` fail, and has to be cleaned up by hand.
