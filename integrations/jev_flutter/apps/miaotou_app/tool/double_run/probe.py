"""The Python half of the double run: a migration instrument, not a port.

It reads the same fixtures as `probe.dart`, runs the remaining comparisons
through Windows `core/draft.py` and `app/update.py`, and prints one canonical
conclusion per area as JSON on stdout for `compare.py` to set against Dart.

Nothing here is imported by anything else and nothing here is a library: it is
deleted with the Windows port it still compares. See README.md beside this file.
"""
import csv
import importlib
import importlib.util
import io
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[5]  # double_run → tool → miaotou_app → apps → jev_flutter → integrations → root
WIN = ROOT / 'integrations' / 'jev_windows'

sys.path.insert(0, str(WIN))


def _load(name, package_init):
    """Loads a Windows package under a private name, keeping relative imports."""
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
