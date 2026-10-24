#!/usr/bin/env python3
"""Summarises balance sim output: python3 tools/balance/report.py OUT_DIR [--md]"""
import collections, glob, json, os, sys

COST = {"runner": 1, "spitter": 1, "fallen": 2, "bloater": 2, "lurker": 2, "shrieker": 2, "brute": 3,
        "leaper": 2, "drifter": 1, "sharpshooter": 2, "burrower": 2}


def load(d):
    rows = []
    for f in sorted(glob.glob(os.path.join(d, "*.jsonl"))):
        for line in open(f):
            line = line.strip()
            if line.startswith("{"):
                rows.append(json.loads(line))
    return rows


def pct(x):
    return f"{100 * x:.0f}%"


def fight_stats(rs):
    n = len(rs)
    win = sum(r["result"] == "win" for r in rs) / n
    to = sum(r["result"] == "timeout" for r in rs) / n
    turns = sum(r["turns"] for r in rs) / n
    lost = sum(min(sum(s["taken"] for s in r["soldiers"]), sum(s["max_hp"] for s in r["soldiers"]))
               / sum(s["max_hp"] for s in r["soldiers"]) for r in rs) / n
    deaths = sum(sum(s["hp"] <= 0 or s["turned"] for s in r["soldiers"]) for r in rs) / n
    return n, win, to, turns, lost, deaths


def table(title, header, rows):
    print(f"\n### {title}\n")
    print("| " + " | ".join(header) + " |")
    print("|" + "---|" * len(header))
    for r in rows:
        print("| " + " | ".join(str(c) for c in r) + " |")


def main():
    rows = load(sys.argv[1])
    by = collections.defaultdict(list)
    for r in rows:
        by[r["tag"].split("|")[0]].append(r)

    # Fights by act and squad size.
    for kind, title in (("fight", "Skirmishes (FightBuilder)"), ("boss", "Boss fights")):
        g = collections.defaultdict(list)
        for r in by[kind]:
            g[(r["act"], r["squad"])].append(r)
        out = []
        for key in sorted(g):
            n, win, to, turns, lost, deaths = fight_stats(g[key])
            out.append([f"act {key[0]}", key[1], n, pct(win), f"{turns:.1f}", pct(lost), f"{deaths:.2f}"])
        table(title, ["act", "squad", "fights", "win", "turns", "squad HP lost", "deaths/fight"], out)

    # Classes inside real fights.
    c = collections.defaultdict(lambda: collections.Counter())
    for r in by["fight"]:
        for s in r["soldiers"]:
            k = c[s["kind"]]
            k["n"] += 1
            k["dealt"] += s["dealt"]
            k["kills"] += s["kills"]
            k["taken"] += s["taken"]
            k["dead"] += s["hp"] <= 0 or s["turned"]
            k["turns"] += r["turns"]
    out = []
    for cls, k in sorted(c.items()):
        out.append([cls, k["n"], f"{k['dealt'] / k['turns']:.2f}", f"{k['kills'] / k['n']:.2f}",
                    f"{k['taken'] / k['n']:.1f}", pct(k["dead"] / k["n"])])
    table("Classes in skirmishes", ["class", "soldier-fights", "damage/turn", "kills/fight", "damage taken/fight", "died"], out)

    # Duels: class x enemy win rate.
    d = collections.defaultdict(list)
    for r in by["duel"]:
        _, cls, e = r["tag"].split("|")
        d[(cls, e)].append(r)
    classes = sorted({k[0] for k in d})
    enemies = sorted({k[1] for k in d})
    out = []
    for cls in classes:
        line = [cls]
        tot = 0
        for e in enemies:
            rs = d[(cls, e)]
            w = sum(r["result"] == "win" for r in rs) / max(1, len(rs))
            tot += w
            line.append(pct(w))
        line.append(pct(tot / len(enemies)))
        out.append(line)
    table("Duels: one soldier vs two of an enemy (win rate)", ["class"] + enemies + ["avg"], out)

    # Enemy threat: full squad vs three of a kind.
    t = collections.defaultdict(list)
    for r in by["threat"]:
        t[r["tag"].split("|")[1]].append(r)
    out = []
    for e, rs in sorted(t.items()):
        n, win, to, turns, lost, deaths = fight_stats(rs)
        dealt = sum(sum(x["dealt"] for x in r["enemies"] if x["kind"] == e) for r in rs) / (3 * n)
        inf = sum(sum(s["infection"] for s in r["soldiers"]) / len(r["soldiers"]) for r in rs) / n
        out.append([e, COST.get(e, "-"), pct(win), f"{turns:.1f}", pct(lost), f"{dealt:.1f}",
                    f"{dealt / COST.get(e, 1):.1f}", f"{inf:.0f}"])
    table("Enemy threat: starter squad vs three of a kind", ["enemy", "cost", "squad win", "turns", "squad HP lost",
                                                             "damage per enemy", "damage per cost", "avg Infection"], out)


if __name__ == "__main__":
    main()
