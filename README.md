# Miaotoujunshi (喵头军师)

Jev Chat's "chat co-pilot" idea, rebuilt as two layers: an independently
distributable AI Skill, plus three app entries — Android, Windows and macOS.

The floating ball reads the screen → you confirm the transcript → analysis →
candidate replies → **one-tap fill, never auto-send**.

## Layout

| Layer | Location | What it is |
| --- | --- | --- |
| Upstream payload | `goutoujunshi/` | The `goutoujunshi` / 狗头军师 payload — `SKILL.md`, `references/`, `agents/`, `assets/`, `scripts/`. A maintained fork of the upstream skill, kept byte-identical; `scripts/check_upstream.py` reports the drift |
| Own payload | `miaotoujunshi/` | This repository's own payload: the shared tone rules (`references/knowledge/`), the structured data (`references/data/`) and the demo cases (`examples/`) all three ports read at runtime. See `docs/adr/0006` |
| Apps | `integrations/jev_flutter`, `integrations/jev_android`, `integrations/jev_windows` | One Flutter app for promoted macOS plus the Windows replacement candidate; frozen Windows and Android remain active until device acceptance |
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

All three application implementations contain derivative logic from the
upstream Jev Chat assistants. The frozen Android and Windows ports ship their
own LICENSE and attribution files; the promoted Flutter macOS implementation's
translated attribution is retained in the root `NOTICE`. See that file for the
MIT/GPL split that applies to each artifact.

**Mind the licence split**: the root is MIT. The new Windows preview artifact is
the Flutter replacement candidate and no longer bundles PySide6-Fluent-Widgets;
the still-tested frozen `integrations/jev_windows` port retains its own licence
notices until device acceptance permits deletion.

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
