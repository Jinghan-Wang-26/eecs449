"""Opt-in, two-call LLM check for partial shopping updates. Uses synthetic context."""
import argparse
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from ai.intents import parse_request
from app_settings import stamp


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    context = {'data_mode':'live', 'planning_requested':False,
               'needs':[{'type':'milk','qty':2,'brand':'TestBrand','size':'1 L'}]}
    cases = [
        ('en_quantity_only', 'Change the milk quantity to three. Keep everything else.', {'type':'milk','qty':3}),
        ('en_remove_brand', 'Remove the milk brand restriction; keep the quantity and package size.', {'type':'milk','brand':''}),
    ]
    result = {'checked_at':stamp(), 'synthetic_context':True, 'cases':[], 'passed':True}
    for name, prompt, expected in cases:
        try:
            actual = parse_request(prompt, context=context)['needs']
            passed = actual == [expected]
            result['cases'].append({'id':name,'expected':[expected],'actual':actual,'passed':passed})
        except ValueError as error:
            passed = False
            result['cases'].append({'id':name,'passed':False,'error':str(error)})
        result['passed'] = result['passed'] and passed
        print(name + ': ' + ('PASS' if passed else 'FAIL'), flush=True)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2)+'\n')
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
