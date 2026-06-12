#!/usr/bin/env python3
"""scripts/check-blackout.py — NovaPay deployment blackout window checker"""
from datetime import datetime, timezone, timedelta
import sys

def check_blackout():
    utc = datetime.now(timezone.utc)
    ist = utc + timedelta(hours=5, minutes=30)
    day, hour, month_day = ist.weekday(), ist.hour, ist.day

    blocked = []
    if month_day in [1, 7, 15]:
        blocked.append(f"Salary day ({month_day}th) — 3-5x UPI volume")
    if month_day in range(28, 32):
        blocked.append(f"Month-end processing (day {month_day}) — batch settlements")
    if 10 <= hour < 12:
        blocked.append(f"Peak UPI hours 10-12 IST ({ist:%H:%M})")
    if 17 <= hour < 20:
        blocked.append(f"Peak UPI hours 17-20 IST ({ist:%H:%M})")

    # Check festival dates (approximate — update annually)
    festival_dates = {
        "Diwali": [(11, 1), (11, 2), (11, 3)],      # Approximate Nov dates
        "Holi":   [(3, 25)],
        "Eid":    [(4, 10), (4, 11)],
        "Christmas": [(12, 24), (12, 25), (12, 26)],
    }
    for name, dates in festival_dates.items():
        if (ist.month, ist.day) in dates:
            blocked.append(f"{name} festival period")

    if blocked:
        print("DEPLOYMENT BLOCKED — Blackout window active:")
        for r in blocked:
            print(f"  ⛔ {r}")
        print(f"\nCurrent IST: {ist:%Y-%m-%d %H:%M}")
        print("For emergency deployments: require CTO + CISO approval and document in change log")
        sys.exit(1)

    print(f"✓ Deployment window CLEAR ({ist:%Y-%m-%d %H:%M} IST)")
    sys.exit(0)

if __name__ == "__main__":
    check_blackout()