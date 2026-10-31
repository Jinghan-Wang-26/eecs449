"""Issue #2: build a need x store coverage matrix near a public origin.

Opt-in real requests; no LLM calls and no changes to any shopping graph.
Kroger needs KROGER_CLIENT_ID/KROGER_CLIENT_SECRET and Geoapify (map-only
supermarkets) needs GEOAPIFY_API_KEY in the local .env. A missing credential
skips that source and is reported as "not_run", never as zero coverage.
Open Prices needs no key.

    python scripts/coverage_matrix.py                    # default: Michigan Union, 8 km
    python scripts/coverage_matrix.py --from-json /tmp/cartcompass-coverage/collection.json

Exit status: 0 when every enabled source ran, 1 when one lacked credentials or failed.
"""
import argparse
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import jaclang  # noqa: F401  Enables imports of the app's Jac matching rules.
from integrations import coverage


def parse(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('--needs', default=','.join(coverage.DEFAULT_NEEDS),
                        help='Comma-separated need categories (default: the ten demo categories).')
    parser.add_argument('--lat', type=float, default=coverage.DEFAULT_ORIGIN['lat'])
    parser.add_argument('--lon', type=float, default=coverage.DEFAULT_ORIGIN['lon'])
    parser.add_argument('--label', default=coverage.DEFAULT_ORIGIN['label'],
                        help='Origin label written to the report. Use a public landmark, never a home address.')
    parser.add_argument('--radius-m', type=int, default=8000)
    parser.add_argument('--max-kroger', type=int, default=5, help='Kroger branches to query (calls = branches x needs).')
    parser.add_argument('--max-openprices', type=int, default=5, help='Open Prices locations with records to query.')
    parser.add_argument('--sources', default=','.join(coverage.SOURCES), help='Subset of: kroger,openprices,map')
    parser.add_argument('--pause', type=float, default=0.1, help='Seconds between requests.')
    parser.add_argument('--out-dir', default='/tmp/cartcompass-coverage')
    parser.add_argument('--from-json', help='Re-summarize a saved collection.json without network requests.')
    args = parser.parse_args(argv)
    args.needs = [n.strip().lower() for n in args.needs.split(',') if n.strip()]
    args.sources = [s.strip() for s in args.sources.split(',') if s.strip()]
    unknown = set(args.sources) - set(coverage.SOURCES)
    if unknown:
        parser.error('unknown source(s): ' + ', '.join(sorted(unknown)))
    if not 1 <= len(args.needs) <= 20:
        parser.error('give 1-20 needs')
    if not 500 <= args.radius_m <= 20000:
        parser.error('--radius-m must be 500-20000')
    if not (0 <= args.max_kroger <= 10 and 0 <= args.max_openprices <= 10):
        parser.error('--max-kroger and --max-openprices must be 0-10')
    return args


def main(argv=None):
    args = parse(argv)
    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    if args.from_json:
        collection = json.loads(Path(args.from_json).read_text())
    else:
        calls = args.max_kroger * len(args.needs) if 'kroger' in args.sources else 0
        print(f'Request budget: up to {calls} Kroger product searches (if configured) and '
              f'{args.max_openprices} Open Prices locations...')
        collection = coverage.collect(args.needs, {'label': args.label, 'lat': args.lat, 'lon': args.lon},
                                      args.radius_m, args.max_kroger, args.max_openprices, args.sources, args.pause)
        (out / 'collection.json').write_text(json.dumps(collection, indent=2) + '\n')
    summary = coverage.summarize(collection)
    (out / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    (out / 'matrix.md').write_text(coverage.render_markdown(summary))
    for name, status in summary['sources'].items():
        print(f"{name}: {status['status']} - {status['detail']}")
    for gap in summary['gaps']:
        print('GAP: ' + gap)
    print(f'Wrote {out}/summary.json and {out}/matrix.md' + ('' if args.from_json else f' (raw rows: {out}/collection.json)'))
    # Sources disabled with --sources are a deliberate choice, not a partial result.
    complete = all(s['status'] in ('ok', 'skipped') for s in summary['sources'].values())
    print('COMPLETE' if complete else 'PARTIAL: some sources were skipped or failed; see above.')
    return 0 if complete else 1


if __name__ == '__main__':
    raise SystemExit(main())
