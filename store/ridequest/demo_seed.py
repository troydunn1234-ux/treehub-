"""Prints a made-up Ride Quest save (seed.json) for App Store screenshots: a fictional person saving for a car.
Dates are relative to today so the current month always has activity. No real data."""
import datetime as dt, json, random

rnd = random.Random(7)
today = dt.date.today()
def day(back): return (today - dt.timedelta(days=back)).isoformat()
n = 0
def uid():
    global n; n += 1; return f"demo{n:04d}"

budgets = [("Groceries", 420), ("Eating out", 160), ("Gas", 190), ("Car care", 90), ("Fun", 120),
           ("Subscriptions", 60), ("Insurance", 150), ("Gym", 40), ("Shopping", 120)]
spots = {"Groceries": ["Trader Joe's", "Safeway", "Farmers market", "Costco"], "Eating out": ["Tacos", "Pho", "Pizza night", "Coffee"],
         "Gas": ["Shell", "Chevron", "Costco Gas"], "Car care": ["Car wash", "Oil change"], "Fun": ["Movies", "Bowling", "Concert"],
         "Shopping": ["Target", "Running shoes", "Books"], "Gym": ["Gym"], "Insurance": ["Car insurance"]}
tx, moves = [], []
for back in range(0, 150):
    d = day(back)
    for cat, names in spots.items():
        p = {"Groceries": .28, "Eating out": .22, "Gas": .14, "Car care": .03, "Fun": .06, "Shopping": .07, "Gym": 0, "Insurance": 0}[cat]
        if rnd.random() < p:
            lo, hi = {"Groceries": (18, 95), "Eating out": (9, 38), "Gas": (38, 62), "Car care": (12, 60), "Fun": (14, 55), "Shopping": (15, 80)}[cat]
            tx.append({"id": uid(), "d": d, "cat": cat, "what": rnd.choice(names), "amt": round(rnd.uniform(lo, hi), 2),
                       "acct": "cash" if rnd.random() < .08 else "checking", "note": ""})
    dd = (today - dt.timedelta(days=back))
    if dd.day == 3:
        tx.append({"id": uid(), "d": d, "cat": "Insurance", "what": "Car insurance", "amt": 142.0, "acct": "checking", "note": ""})
        tx.append({"id": uid(), "d": d, "cat": "Gym", "what": "Gym", "amt": 39.99, "acct": "checking", "note": ""})
    if dd.day == 9:
        for what, amt in (("Music streaming", 10.99), ("Video streaming", 15.49), ("Cloud storage", 2.99)):
            tx.append({"id": uid(), "d": d, "cat": "Subscriptions", "what": what, "amt": amt, "acct": "checking", "note": ""})
    if dd.weekday() == 4 and (dd.isocalendar()[1] % 2 == 0):   # payday every other Friday
        moves.append({"id": uid(), "d": d, "from": "outside", "to": "checking", "amt": 1680.0, "note": "Paycheck"})
        moves.append({"id": uid(), "d": d, "from": "checking", "to": "savings", "amt": rnd.choice([350.0, 400.0, 450.0]), "note": "Payday stash"})
subs = [
    {"id": uid(), "n": "Music streaming", "amt": 10.99, "cyc": "monthly", "next": (today.replace(day=9) + dt.timedelta(days=31)).replace(day=9).isoformat(), "st": "active", "cat": "streaming", "via": "apple"},
    {"id": uid(), "n": "Video streaming", "amt": 15.49, "cyc": "monthly", "next": (today.replace(day=9) + dt.timedelta(days=31)).replace(day=9).isoformat(), "st": "active", "cat": "streaming", "via": "paypal"},
    {"id": uid(), "n": "Cloud storage", "amt": 2.99, "cyc": "monthly", "next": (today.replace(day=9) + dt.timedelta(days=31)).replace(day=9).isoformat(), "st": "active", "cat": "cloud", "via": "apple"},
    {"id": uid(), "n": "Gym", "amt": 39.99, "cyc": "monthly", "next": (today.replace(day=3) + dt.timedelta(days=31)).replace(day=3).isoformat(), "st": "active", "cat": "fitness", "via": "card"},
    {"id": uid(), "n": "Photo app", "amt": 4.99, "cyc": "monthly", "next": (today + dt.timedelta(days=6)).isoformat(), "st": "active", "cat": "ai", "trialEnds": (today + dt.timedelta(days=6)).isoformat()},
    {"id": uid(), "n": "Language app", "amt": 59.99, "cyc": "yearly", "next": (today + dt.timedelta(days=40)).isoformat(), "st": "cancel", "note": "Haven't opened it in months", "cat": "other"},
]
state = {
    "start": {"savings": 9800, "checking": 900, "cash": 600},
    "goal": {"name": "Dream car", "amount": 59495, "by": f"{today.year + 2}-08", "monthly": 900},
    "weekGoal": 200, "weekStart": 5, "rev": 1, "boot": 0, "theme": "neon", "sound": 0,
    "budgets": [{"n": n_, "l": l} for n_, l in budgets],
    "bills": [{"id": uid(), "n": "Car insurance", "amt": 142.0, "day": 3}, {"id": uid(), "n": "Phone", "amt": 45.0, "day": 18},
              {"id": uid(), "n": "Rent", "amt": 1150.0, "day": 1}],
    "tx": tx, "moves": moves, "subs": subs,
}
print(json.dumps({"budget/main": {"state": state}}))
