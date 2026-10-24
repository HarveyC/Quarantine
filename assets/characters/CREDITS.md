# Characters: credits and how they're built

Every unit except the Bloom's props and the Drifter is a skinned character built by
`tools/build_characters.py` from public-domain (CC0 1.0) art by **Quaternius**
(https://quaternius.com), dressed with our own scripted gear, weapons and infection growths.

| Used for | Pack | Source | Licence |
|---|---|---|---|
| All humanoid bodies (squad, civilians, the infected, turned soldiers, Hale) | Universal Base Characters (Standard) | https://quaternius.itch.io/universal-base-characters | CC0 1.0 |
| Clips in `anims_ual1.glb` (idle, jog, crouch, hit, death, punch, jump, ...) | Universal Animation Library (Standard) | https://quaternius.itch.io/universal-animation-library | CC0 1.0 |
| Clips in `anims_ual2.glb` (zombie idle / walk / scratch, throw, radio call, ...) | Universal Animation Library 2 (Standard) | https://quaternius.itch.io/universal-animation-library-2 | CC0 1.0 |
| Lurker and Burrower body and clips | Spider, from Animated Enemies | https://poly.pizza/m/yRYJiAJyiM | CC0 1.0 |

CC0 needs no attribution; we credit Quaternius anyway. The untouched source zips and their
licence texts are kept on the repository's `cc0-assets-1` prerelease (see its LICENSES.md).
Only the free Standard tiers were used, and only files marked CC0 (no CC-BY models).

`textures/` holds the base characters' body textures, downscaled to 1024 px and shared by
every character (the glTF files carry no images).

## What is ours

Gear (helmets, plate carriers, pads, packs, the medic's kit, the breacher's shield), the
four rifles, the fatigues / rags / coats (copies of the body surface pushed out, so they
keep its skinning), infection growths and crystals, claws, sacs and egg clusters are all
built from code with the primitives in `tools/gen_models.py`.

## Rebuild

    # once: download the cc0-assets-1 zips and unzip each into ~/cc0/x/<zip name>/
    pip install bpy                       # Blender as a Python module (or run inside Blender 4.2+)
    python3 tools/build_characters.py     # everything, or name some: anims trooper runner ...

Then reopen the project in Godot so it reimports. `view/skinned_body.gd` plays the clips;
`view/model_kit.gd` maps material names to the character shader's roles.
