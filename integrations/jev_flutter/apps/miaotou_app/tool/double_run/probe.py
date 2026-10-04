"""The Python half of the double run: a migration instrument, not a port.

It reads the same fixtures as `probe.dart`, runs them through the *existing*
implementations — macOS `core.py`, `ranking.py`, `trend.py`, `experience.py` and
Windows `core/draft.py`, `app/update.py` — and prints one canonical conclusion
per area as JSON on stdout, in the same shape the Dart probe prints, for
`compare.py` to set the two against each other.

Nothing here is imported by anything else and nothing here is a library: it is
deleted together with the ports it compares. See README.md beside this file.

Two imports need explaining:

* macOS has a `core` module and Windows has a `core` package, and both are on
  `sys.path`. macOS wins the name (it is inserted first and `experience` and
  `trend` import it by that name); Windows' `core` is loaded under the private
  name `win_core` so its own relative imports still resolve.
* `ranking` imports `complete` from `client`, which is the network layer. Scoring
  never calls it, and no fixture reaches it, so no stub is installed beyond the
  import itself — if it were called, the run would fail loudly rather than
  quietly differ.
"""
import csv
import importlib
import importlib.util
import io
import json
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[5]  # double_run → tool → miaotou_app → apps → jev_flutter → integrations → root
MAC = ROOT / 'integrations' / 'jev_mac'
WIN = ROOT / 'integrations' / 'jev_windows'

sys.path.insert(0, str(WIN))
sys.path.insert(0, str(MAC))

import core as mac_core  # noqa: E402  macOS core.py
import experience  # noqa: E402
import ranking  # noqa: E402
import trend as mac_trend  # noqa: E402


def _load(name, package_init):
    """Loads a Windows module under a private name, keeping its relative imports.

    Both ports have a `core` and an `app`; macOS owns the two bare names because
    `experience` and `trend` import it that way, so Windows' are reached through
    this alias instead.
    """
    spec = importlib.util.spec_from_file_location(
        name, package_init, submodule_search_locations=[str(package_init.parent)])
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


_load('win_core', WIN / 'core' / '__init__.py')
_load('win_app', WIN / 'app' / '__init__.py')
draft = importlib.import_module('win_core.draft')
win_update = importlib.import_module('win_app.update')


def _raw(fixture):
    """The answer as the model would have sent it: a string, not a structure."""
    if 'raw_text' in fixture:
        return fixture['raw_text']
    return json.dumps(fixture['answer'], ensure_ascii=False)


def _candidates(rows):
    return [{'text': row['text'], 'reason': row['reason'], 'tradeoff': row['tradeoff']}
            for row in rows]


def injection(fixture):
    """#10 — Windows `core/draft.py`: suspects, recent lines, survivors."""
    messages = [tuple(m) for m in fixture['messages']]
    suspects = draft._suspects(messages, 10)
    recent = draft._her_recent(messages, 5)
    return {
        'id': fixture['id'],
        'suspects': suspects,
        'recent': recent,
        'survivors': draft._sanitize(list(fixture['candidates']), suspects, recent),
    }


def advice(fixture):
    """#7 — macOS `core.parse_advice`."""
    try:
        data = mac_core.parse_advice(_raw(fixture))
    except ValueError:
        return {'id': fixture['id'], 'ok': False}
    return {
        'id': fixture['id'],
        'ok': True,
        'intent': data.get('intent'),
        'confidence': data.get('intent_confidence'),
        'strategy': data['strategy'],
        'support': data['support'],
        'recommendation': data['recommendation'],
        'next_step': data['next_step'],
        'stop_condition': data['stop_condition'],
        'question': data['question'],
        'facts': data['facts'],
        'hypotheses': data['hypotheses'],
        'unknowns': data['unknowns'],
        'candidates': _candidates(data['candidates']),
    }


def rewrite(fixture):
    """#7 — macOS `core.parse_rewrite`."""
    try:
        rows = mac_core.parse_rewrite(_raw(fixture), fixture['strategy'])
    except ValueError:
        return {'id': fixture['id'], 'ok': False}
    return {'id': fixture['id'], 'ok': True, 'candidates': _candidates(rows)}


def scoring(fixture):
    """#7 — macOS `ranking.apply_scores`."""
    try:
        rows = ranking.apply_scores([dict(row) for row in fixture['candidates']], _raw(fixture))
    except ValueError:
        return {'id': fixture['id'], 'ok': False}
    return {
        'id': fixture['id'],
        'ok': True,
        'ranked': [{'text': row['text'], 'weight': row['weight']} for row in rows],
    }


def chat_csv(fixture):
    """#8 — macOS `trend.load_csv`, which reads a file rather than bytes."""
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / 'chat.csv'
        path.write_text(fixture['csv'], encoding='utf-8')
        try:
            result = mac_trend.load_csv(path)
        except ValueError:
            return {'id': fixture['id'], 'ok': False}
        return {
            'id': fixture['id'],
            'ok': True,
            'messages': result.messages,
            'candles': [{
                'date': candle.date,
                'open': candle.open,
                'high': candle.high,
                'low': candle.low,
                'close': candle.close,
                'mine': candle.mine,
                'other': candle.other,
                'events': list(candle.events),
            } for candle in result.candles],
        }


def profile(fixture):
    """#9 — macOS `experience.validate_profile` and `profile_context`."""
    row = dict(fixture['profile'])
    try:
        experience.validate_profile(row)
    except ValueError:
        return {'id': fixture['id'], 'ok': False, 'context': None}
    return {
        'id': fixture['id'],
        'ok': True,
        'context': json.loads(experience.profile_context(row)),
    }


def update(fixture):
    """#10 — Windows `app/update.py`'s decision, without its network call.

    `check_latest` fetches the release and then decides. The fetch is the wire
    and is not ported; what is replayed here is the decision it would have
    reached for the tag the fixture supplies, using its own `parse_version`.
    """
    current = win_update.parse_version(fixture['current'])
    tag = fixture['tag'][1:] if fixture['tag'].startswith('v') else fixture['tag']
    latest = win_update.parse_version(tag)
    reports = (current is not None and latest is not None
               and bool(fixture['url']) and latest > current)
    return {'id': fixture['id'], 'reports': reports, 'tag': tag if reports else None}


def csv_grid(fixture):
    """#8 — the round trip Python's own `csv` module must satisfy."""
    grid = [list(row) for row in fixture['grid']]
    buffer = io.StringIO()
    csv.writer(buffer, lineterminator='\n').writerows(grid)
    back = list(csv.reader(io.StringIO(buffer.getvalue())))
    return {'id': fixture['id'], 'round_trip': back == grid, 'back': back}


AREAS = {
    'injection': injection,
    'advice': advice,
    'rewrite': rewrite,
    'scoring': scoring,
    'chat_csv': chat_csv,
    'profile': profile,
    'update': update,
    'csv_grid': csv_grid,
}


def main():
    fixtures = json.loads((HERE / 'fixtures.json').read_text(encoding='utf-8'))
    report = {area: [run(fixture) for fixture in fixtures[area]]
              for area, run in AREAS.items()}
    sys.stdout.write(json.dumps(report, ensure_ascii=False) + '\n')


if __name__ == '__main__':
    main()
