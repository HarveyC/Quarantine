#!/usr/bin/env python3
"""Runs the balance sim in parallel and writes one JSONL file per batch.

    GODOT=path/to/godot python3 tools/balance/run_sims.py OUT_DIR [--quick] [--only=fight,boss,real,nest,nestpurge,purge,melee,meleeboss,duel,threat]

Then: python3 tools/balance/report.py OUT_DIR
"""
import itertools, json, os, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GODOT = os.environ.get("GODOT", "godot")
STARTERS = ["trooper", "marksman", "medic", "breacher"]
MELEE = ["reaper", "warden"]
ALL = STARTERS + ["hazmat", "vector"] + MELEE
# Mid-act Outbreak per act for the "real" batches; RUN_OUTBREAK=2,4,6 overrides it.
RUN_OUTBREAK = dict(zip((1, 2, 3), map(int, os.environ.get("RUN_OUTBREAK", "3,6,9").split(","))))
REGULARS = ["runner", "spitter", "fallen", "bloater", "leaper", "brute", "lurker", "drifter",
            "sharpshooter", "shrieker", "burrower", "hooker", "sapper", "carapace", "stalker", "weaver"]


def batches(quick):
    k = 1 if quick else 3
    out = []
    # Real fights from FightBuilder: every squad size, every starter-class mix, every act.
    for size in (1, 2, 3, 4):
        combos = list(itertools.combinations(STARTERS, size))
        per = max(4, (24 * k) // len(combos))
        for act in (1, 2, 3):
            for combo in combos:
                out.append(dict(tag=f"fight|a{act}|s{size}|{'+'.join(combo)}", squad=",".join(combo),
                                act=act, node="skirmish", n=per))
            for combo in combos[: max(1, len(combos) // 2)]:
                out.append(dict(tag=f"boss|a{act}|s{size}|{'+'.join(combo)}", squad=",".join(combo),
                                act=act, node="boss", n=max(6, per)))
    # Run-like pressure: the Outbreak a squad typically has mid-act (+1 per node, -3 per boss), on
    # plain skirmishes and on Infested nests (an elite every fight).
    for size in (1, 2, 3, 4):
        combos = list(itertools.combinations(STARTERS, size))
        per = max(4, (16 * k) // len(combos))
        for act in (1, 2, 3):
            for combo in combos:
                out.append(dict(tag=f"real|a{act}|s{size}|{'+'.join(combo)}", squad=",".join(combo),
                                act=act, node="skirmish", outbreak=RUN_OUTBREAK[act], n=per))
                out.append(dict(tag=f"nest|a{act}|s{size}|{'+'.join(combo)}", squad=",".join(combo),
                                act=act, node="nest", outbreak=RUN_OUTBREAK[act], n=max(3, per // 2)))
                out.append(dict(tag=f"nestpurge|a{act}|s{size}|{'+'.join(combo)}", squad=",".join(combo),
                                act=act, node="nest", objective="purge", outbreak=RUN_OUTBREAK[act], n=max(3, per // 2)))
                out.append(dict(tag=f"purge|a{act}|s{size}|{'+'.join(combo)}", squad=",".join(combo),
                                act=act, node="skirmish", objective="purge", outbreak=RUN_OUTBREAK[act], n=max(3, per // 2)))
    # Melee classes in real squads: one melee soldier swapped into starter mixes, every act.
    melee_squads = [[m] for m in MELEE] + [[m, o] for m in MELEE for o in ("trooper", "medic", "marksman")] \
        + [["trooper", "marksman", "medic", m] for m in MELEE] + [["reaper", "warden"], ["reaper", "warden", "medic", "marksman"]]
    for act in (1, 2, 3):
        for combo in melee_squads:
            out.append(dict(tag=f"melee|a{act}|s{len(combo)}|{'+'.join(combo)}", squad=",".join(combo),
                            act=act, node="skirmish", n=8 * k))
            if len(combo) >= 2:
                out.append(dict(tag=f"meleeboss|a{act}|s{len(combo)}|{'+'.join(combo)}", squad=",".join(combo),
                                act=act, node="boss", n=4 * k))
    # Class duels: one soldier against two of each regular enemy (act 1 rank).
    for cls in ALL:
        for e in REGULARS:
            out.append(dict(tag=f"duel|{cls}|{e}", squad=cls, act=1, node="skirmish",
                            enemies=f"{e},{e}", n=6 * k))
    # Enemy threat: the full starter squad against three of one kind.
    for e in REGULARS:
        out.append(dict(tag=f"threat|{e}", squad=",".join(STARTERS), act=1, node="skirmish",
                        enemies=",".join([e] * 3), n=8 * k))
    return out


def run(b, out_dir, idx):
    args = [f"{key}={val}" for key, val in b.items()]
    args.append(f"seed={1000 + idx * 97}")
    res = subprocess.run([GODOT, "--headless", "--path", ROOT, "-s", "tools/balance/balance_sim.gd", "--"] + args,
                         capture_output=True, text=True, timeout=3600)
    lines = [l for l in res.stdout.splitlines() if l.startswith("{")]
    with open(os.path.join(out_dir, f"{idx:04d}.jsonl"), "w") as f:
        f.write("\n".join(lines) + "\n")
    errs = [l for l in res.stdout.splitlines() + res.stderr.splitlines() if "SCRIPT ERROR" in l]
    return b["tag"], len(lines), errs[:3]


def main():
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    todo = batches("--quick" in sys.argv)
    only = [a.split("=", 1)[1].split(",") for a in sys.argv if a.startswith("--only=")]
    if only:
        todo = [b for b in todo if b["tag"].split("|")[0] in only[0]]
    with ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as ex:
        futs = [ex.submit(run, b, out_dir, i) for i, b in enumerate(todo)]
        for i, f in enumerate(futs):
            tag, n, errs = f.result()
            print(f"[{i + 1}/{len(todo)}] {tag}: {n} fights" + (f"  ERRORS: {errs}" if errs else ""), flush=True)


if __name__ == "__main__":
    main()
