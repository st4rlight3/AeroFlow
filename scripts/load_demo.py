"""One entry point for domestic, international and travel demo catalogues.

Preview does not open a database. --apply imports each catalogue atomically;
all stages are idempotent, so a failed stage can safely be retried. Apply
migrations 001–023 first. Existing customer/ticket/payment history is retained.
"""
import argparse
from dataclasses import asdict
import json
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from scripts.seed_ultimate import resolve_window,seed_demo
from scripts.seed_international import seed_international
from scripts.demo_catalog import preview as domestic_preview
from scripts.international_catalog import preview as international_preview
from scripts.seed_travel import seed as seed_travel,CATEGORIES,DESTINATIONS


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    mode=parser.add_mutually_exclusive_group()
    mode.add_argument('--apply',action='store_true')
    mode.add_argument('--preview',action='store_true')
    parser.add_argument('--days',type=int)
    parser.add_argument('--start-date')
    args=parser.parse_args()
    try:
        days,start=resolve_window(args.days,args.start_date)
        domestic=domestic_preview(days,start);world=international_preview(days,start)
        result=dict(mode='APPLIED' if args.apply else 'PREVIEW_ONLY',start_date=start.isoformat(),days=days,
                    total_new_catalogue_flights=domestic['planned_flights']+world['planned_international_flights'],
                    domestic=domestic,international=world)
        result['travel']=dict(destinations=len(DESTINATIONS),products=len(DESTINATIONS)*len(CATEGORIES),packages=len(DESTINATIONS)*len(CATEGORIES)*2,inventory=len(DESTINATIONS)*len(CATEGORIES)*2*days)
        if args.apply:
            result['domestic_result']=asdict(seed_demo(days,start))
            result['international_result']=asdict(seed_international(days,start))
            result['travel_result']=seed_travel(start,days)
    except (ValueError,RuntimeError) as error:parser.error(str(error))
    print(json.dumps(result,ensure_ascii=False,indent=2))


if __name__=='__main__':main()
