#!/usr/bin/env python3
"""Build the whole icon set (dev tool, needs GEMINI_API_KEY and Pillow):

    python3 tools/gen_icon_set.py [--only name,name] [--force]

Writes tinted-white glow masks to assets/icons/<id>.png (UI vocabulary) and
assets/icons/items/<id>.png (gear, guns, consumables, orders). Skips files that exist.
"""
import os, re, sys, importlib.util
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location("gen_icons", os.path.join(ROOT, "tools/gen_icons.py"))
G = importlib.util.module_from_spec(spec); os.environ.setdefault("ICON_STYLE", "glow"); spec.loader.exec_module(G)

VOCAB = {
    # route nodes
    "skirmish": "two crossed combat knives", "ambush": "a spring trap with a jagged maw", "nest": "a cluster of three egg pods",
    "event": "a radio mast sending a signal", "depot": "a stack of supply crates", "hospital": "a field medical tent with a lantern",
    "survivors": "a small group of three huddled people silhouettes", "boss": "a horned monstrous skull", "unknown": "a closed door with a keyhole and a question mark-like curl, no letters",
    # action wheel
    "shoot": "a rifle crosshair scope reticle", "overwatch": "a single simple open eye, almond shape with a round iris and pupil, nothing else, symmetrical", "reload": "a rifle magazine sliding in with a curved arrow",
    "hunker": "a soldier crouched behind a low wall", "tag": "a targeting marker pin with radiating ticks", "suppress": "a fan-shaped cone of five bullets spreading outward from one point, bullet tips pointing away, simple and symmetrical",
    "breach": "a door blown inward with a burst of fragments", "grenade": "a frag grenade with pin", "charge": "a demolition charge brick with a wire and timer",
    "smoke": "a smoke grenade venting a cloud", "flash": "a flashbang grenade with a bright starburst", "drone": "a small quadcopter recon drone",
    "medic": "a medical cross over a syringe", "purge": "a vial pouring clean drops onto a spore", "incinerate": "a flamethrower nozzle with a flame",
    "siphon": "a syringe drawing a swirl of fluid into a vial", "cure": "a breather mask with a filter", "lock": "a padlock with foam seals",
    "mutation": "a twisting double helix growing a thorn", "ability": "an eight-pointed star burst", "cover_half": "a waist-high concrete barrier",
    "move": "a boot print with a forward arrow", "lunge": "a dagger thrust forward with motion lines", "bash": "a clenched armoured fist striking",
    "guard": "a heavy tower shield", "shield_charge": "a tower shield rushing forward with motion lines", "bloom_claw": "a hooked organic claw",
    "runner_leap": "a clawed figure leaping with motion lines",
    # signature abilities (PR #144)
    "lockdown": "a closing steel cage grid", "deadeye": "a round sniper scope lens with a single eye-like pupil, circular composition", "quarantine_field": "a hexagonal energy dome",
    "bring_down": "a toppling scaffold tower falling", "flashover": "a room igniting into a fireball burst", "vent": "a steam valve venting gas",
    "death_sweep": "a wide scythe slash arc", "provoke": "a taunting shouting mouth with sound waves, no teeth, no text",
    # glossary and status icons
    "alert": "an exclamation-like alarm bell ringing, no text", "amputate": "a surgical bone saw", "armor": "a plate carrier body armor vest",
    "attack": "a combat knife striking with a slash arc", "barrel": "a fuel drum barrel with a flame mark", "clock": "a round wall clock showing the passage of turns, no numerals",
    "concealed": "a hooded figure half hidden in shadow", "consumable": "a single-use injector vial", "danger": "a hazard warning triangle with a jagged crack, no text",
    "detected": "a wide open eye with a red alert ring, no text", "doctrine": "a folded battle-plan scroll with a seal", "enemy": "a hostile infected creature head with spines",
    "flag": "an objective flag on a pole", "graft": "a mechanical arm joint fused with organic tendrils", "health": "a beating heart with a pulse line",
    "infection": "a spore cluster with creeping tendrils", "intel": "a data tablet with a magnifying lens", "kill": "a skull crossed with a bullet",
    "loadout": "an open gear case with items in slots", "outbreak": "an expanding ring of spore bursts", "patch": "a bandage patch cross-stitched",
    "perk": "a rising chevron stack star", "pinned": "a soldier pinned down under crossed bullet lines", "plus": "a bold plus sign",
    "rank": "a military rank chevron badge", "recruit": "a new soldier helmet with a plus", "refit": "a wrench and gear over a mechanical limb",
    "reveal": "an eye opening with light rays", "serum": "a glowing vial of serum with a dropper", "skull": "a human skull",
    "stun": "a dazed head with spiral eyes and stars", "supplies": "a crate of supplies with a cog", "train": "a dumbbell with a rising arrow",
    "turn": "a circular arrow cycling around a flag", "turned": "a soldier head half transformed into spores", "weapon": "an assault rifle, side view",
    "wound": "a gash wound with stitches",
    # menus and lobby
    "continue": "a bold right-pointing play triangle with a circular arrow looping around it", "solo": "a single soldier helmet and shoulders, front view",
    "coop": "two soldier helmets side by side with linked hands, simple", "online": "a globe with latitude and longitude lines and a signal arc",
    "join": "an open doorway with an arrow entering it", "hotseat": "two soldier helmets facing each other over a shared screen",
    "quick": "a lightning bolt over a crosshair ring", "settings": "a gear cog with a centre hole, eight teeth",
    "leave": "an open doorway with an arrow exiting it", "lantern": "a hand lantern with a handle and a glowing flame",
    "waiting": "an hourglass", "buy": "a hand dropping a coin into an open crate", "sell": "a crate with a coin leaving it and an upward arrow",
    "cart": "a small supply cart with two wheels", "route": "a dotted winding path linking three nodes", "squad": "a row of three soldier helmets",
    "trophy": "a laurel-wrapped trophy cup", "victory": "a raised flag planted on a mound with rays", "vote": "a ballot box with a slot and a tick-like mark, no letters",
    "ping": "a map marker pin with radiating signal rings", "pause": "two bold vertical bars inside a ring", "reroll": "two circular arrows chasing each other around a die",
    "keyboard": "a keyboard seen from above with a few keycaps", "music": "a musical note pair with a sound wave", "sound": "a loudspeaker with three sound arcs",
    "ambience": "a drifting cloud with wind lines", "effects": "a starburst explosion with sparks", "interface": "a window frame with a cursor arrow",
    "master": "a mixing console fader slider", "mute": "a loudspeaker crossed by a slash", "menu": "a stack of three horizontal bars with rounded ends",
    "ammo": "a bullet cartridge standing upright", "gadget": "a handheld tactical device with an antenna", "bloom": "a blooming spore flower with open petals",
    "struggle": "two hands gripping and pulling a chain", "draw": "a card fanned in a hand, two cards",
    # classes
    "trooper": "a soldier helmet with a chevron", "marksman": "a sniper rifle scope crosshair", "breacher": "a compact square emblem: a heavy door-breaching ram head with a spark burst, tall and squat shape",
    "reaper": "a hooded scythe blade", "warden": "a riot shield with a baton", "hazmat": "a gas mask respirator", "vector": "a hypodermic injector with a spreading burst",
}
ITEM_HINT = {"weapon": "a weapon attachment", "ammo": "ammunition", "armor": "a piece of body armor", "gadget": "a tactical gadget"}


def parse(path, start, end):
    s = open(os.path.join(ROOT, path)).read()
    s = s[s.index(start):s.index(end)] if end else s[s.index(start):]
    return re.findall(r'^\t"(\w+)":\s*\{"name": "([^"]+)"[^\n]*?(?:"slot": "(\w+)")?[^\n]*\n?(?:\t\t"desc": "([^"]*)")?', s, re.M)


def jobs():
    out = {}
    for k, p in VOCAB.items():
        out[f"assets/icons/{k}.png"] = p
    for gid, name, slot, desc in parse("gear/gear_data.gd", "const ITEMS := {", "const PROTOTYPES := {") + parse("gear/gear_data.gd", "const PROTOTYPES := {", "const CONSUMABLES := {"):
        out[f"assets/icons/items/{gid}.png"] = f"{name}: {ITEM_HINT.get(slot, 'a piece of gear')}, hint: {desc[:70]}"
    for gid, name, slot, desc in parse("gear/gear_data.gd", "const CONSUMABLES := {", "const CONSUMABLE_CHARGES"):
        out[f"assets/icons/items/{gid}.png"] = f"{name}, a one-use field consumable, hint: {desc[:70]}"
    for gid, name, slot, desc in parse("gear/deploy_orders.gd", "const ORDERS := {", "static func is_risky"):
        out[f"assets/icons/items/{gid}.png"] = f"{name}: a sealed requisition case of gear, hint: {desc[:70]}"
    s = open(os.path.join(ROOT, "combat/weapons.gd")).read()
    s = s[s.index("const TABLE := {"):]
    for gid, name in re.findall(r'^\t"(\w+)":\s*\{[^\n]*?"name": "([^"]+)"', s, re.M):
        out[f"assets/icons/items/{gid}.png"] = f"{name}, a firearm, side view"
    return out


def one(item):
    path, prompt = item
    full = os.path.join(ROOT, path)
    for attempt in range(3):
        try:
            G.to_mask(G.generate(prompt)).save(full)
            return path, True
        except Exception as e:
            err = e
    return path, f"failed: {err}"


if __name__ == "__main__":
    only = None
    if "--only" in sys.argv:
        only = set(sys.argv[sys.argv.index("--only") + 1].split(","))
    force = "--force" in sys.argv
    todo = [(p, q) for p, q in jobs().items() if (force or not os.path.exists(os.path.join(ROOT, p)))
            and (only is None or os.path.basename(p)[:-4] in only)]
    for p, _ in todo:
        os.makedirs(os.path.dirname(os.path.join(ROOT, p)), exist_ok=True)
    print(len(todo), "to generate")
    with ThreadPoolExecutor(6) as ex:
        for path, ok in ex.map(one, todo):
            print(path, ok)
