# Prop models

The Drifter and the Bloom's static props (hive node, egg sac, spore nest, Source root,
the Source) are original, generated for Quarantine by `tools/gen_models.py` (Blender,
scripted). No third-party meshes or textures.

    python3 tools/gen_models.py                    # with `pip install bpy`, or inside Blender
    python3 tools/gen_models.py -- egg_sac drifter # only some

Soldiers, civilians and the infected are skinned CC0 characters: see
`assets/characters/CREDITS.md`. Shading lives in `view/character.gdshader`; material roles
are mapped in `view/model_kit.gd`.
