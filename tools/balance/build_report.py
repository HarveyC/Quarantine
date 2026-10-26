#!/usr/bin/env python3
"""Win rate and HP lost by build quality (the `build` and `buildboss` batches of run_sims.py).

    python3 tools/balance/build_report.py OUT_DIR              # tables against the target curve
    python3 tools/balance/build_report.py BASE_DIR VARIANT_DIR # the same, base -> variant, for a balance change

Act win = the whole act (3 skirmishes then the boss, HP and deaths carried over) cleared.
Boss alone = the boss fight from a fresh squad at full HP.
HP lost = damage taken per fight as a share of squad max HP, pooled over every fight of the act.
"""
import collections, glob, json, os, sys

LEVELS = ["none", "scattered", "lane", "full"]
# Act win targets (Harvey 2026-10-25): Act 1 easy for everyone, Act 3 a build check.
TARGET = {(1, l): 0.95 for l in LEVELS}
TARGET.update({(3, "none"): 0.10, (3, "scattered"): 0.25, (3, "full"): 0.85})


def load(d):
    rows = []
    for f in sorted(glob.glob(os.path.join(d, "*.jsonl"))):
        for line in open(f):
            if line.startswith("{"):
                rows.append(json.loads(line))
    return rows


def group_of(tag):
    _, _, _, size, mix = tag.split("|")
    size = size[1:]
    return size + (" new classes" if "hazmat" in mix else " starters" if size == "4" else "")


def summarise(rows):
    """{(kind, act, group, level): stats}"""
    cells = collections.defaultdict(list)
    for r in rows:
        kind = r["tag"].split("|")[0]
        if kind in ("build", "buildboss"):
            cells[(kind, r["act"], group_of(r["tag"]), r["build"])].append(r)
    out = {}
    for key, rs in cells.items():
        n = len(rs)
        if key[0] == "build":
            wins = sum(r["result"] == "win" for r in rs)
            taken = sum(f["taken"] for r in rs for f in r["fights"])
            pool = sum(f["pool"] for r in rs for f in r["fights"])
            peak = sum(r["peak_tag"] for r in rs) / n
            out[key] = {"n": n, "win": wins / n, "lost": taken / max(1, pool), "peak": peak}
        else:
            wins = sum(r["result"] == "win" for r in rs)
            taken = sum(sum(s["taken"] for s in r["soldiers"]) for r in rs)
            pool = sum(sum(s["max_hp"] for s in r["soldiers"]) for r in rs)
            out[key] = {"n": n, "win": wins / n, "lost": taken / max(1, pool)}
    return out


def pct(x):
    return f"{100 * x:.0f}%"


def cell(a, b, field="win"):
    if a is None:
        return "-"
    if b is None:
        return pct(a[field])
    d = round(100 * (b[field] - a[field]))
    return f"{pct(a[field])} to {pct(b[field])} ({d:+d})"


def table(title, header, rows):
    print(f"\n### {title}\n")
    print("| " + " | ".join(header) + " |")
    print("|" + "---|" * len(header))
    for r in rows:
        print("| " + " | ".join(str(c) for c in r) + " |")


def main():
    base = summarise(load(sys.argv[1]))
    var = summarise(load(sys.argv[2])) if len(sys.argv) > 2 else None
    groups = sorted({k[2] for k in base}, key=lambda g: (int(g[0]), g))
    for act in (1, 2, 3):
        for kind, title, field, label in (("build", "act win", "win", "Act %d cleared"),
                                          ("build", "squad HP lost per fight", "lost", "Act %d HP lost per fight"),
                                          ("buildboss", "boss alone win", "win", "Act %d boss alone, win")):
            rows = []
            for g in groups:
                line = [g]
                for l in LEVELS:
                    k = (kind, act, g, l)
                    line.append(cell(base.get(k), var.get(k) if var else None, field))
                rows.append(line)
            if field == "win" and kind == "build":
                # Pooled over all squad groups, with the target beside it.
                line = ["all squads"]
                for l in LEVELS:
                    vs = [v for k, v in base.items() if k[:2] == (kind, act) and k[3] == l]
                    ws = [v for k, v in (var or base).items() if k[:2] == (kind, act) and k[3] == l]
                    pool = lambda xs: sum(v["win"] * v["n"] for v in xs) / max(1, sum(v["n"] for v in xs))
                    line.append(pct(pool(vs)) if var is None else f"{pct(pool(vs))} to {pct(pool(ws))}")
                rows.append(line)
                rows.append(["target"] + [pct(TARGET[(act, l)]) if (act, l) in TARGET else "open" for l in LEVELS])
            table(label % act, ["squad"] + LEVELS, rows)
    peaks = []
    for g in groups:
        peaks.append([g] + [f"{base[('build', 3, g, l)]['peak']:.1f}" if ('build', 3, g, l) in base else "-" for l in LEVELS])
    table("Act 3 most pieces on one tag, per soldier (capstone at 6)", ["squad"] + LEVELS, peaks)
    n_runs = sum(v["n"] for k, v in base.items() if k[0] == "build")
    print(f"\n{n_runs} act runs, {sum(v['n'] for k, v in base.items() if k[0] == 'buildboss')} boss fights in the base set.")


if __name__ == "__main__":
    main()
