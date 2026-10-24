# Character models

All soldier and enemy models in this folder are original and were generated for
Quarantine by `tools/gen_models.py` (Blender, scripted). No third-party meshes,
textures or animations are used, so there is nothing to attribute or license-check.

Regenerate after editing the script:

    blender --background --python tools/gen_models.py      # or: pip install bpy; python3 tools/gen_models.py
    blender --background --python tools/gen_models.py -- runner spitter   # only some models

Why scripted rather than a CC0 pack (Quaternius / Kenney / Mixamo-style clips):
- The infection growths have to be authored per rig and per tier, and the class
  silhouettes (radio antenna, hood and long rifle, white trauma pack, forearm shield)
  needed custom parts anyway.
- One script keeps the whole cast in one style and makes changes cheap: tweak a
  number, rerun, and every model updates.
- The game animates joints procedurally (walk, aim with arm IK, recoil, hit, lunge,
  death), so no baked animation clips are needed.
A CC0 humanoid base could still be swapped in later as long as it keeps the joint
names documented at the top of the script.

Shading lives in `view/character.gdshader`; material roles are mapped in `view/model_kit.gd`.
