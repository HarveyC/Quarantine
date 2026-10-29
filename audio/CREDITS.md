# Audio credits

Every sound in this folder is original: synthesized from code (noise, oscillators,
filters, formant voices, convolution reverb, fixed random seeds). No third-party samples
are used, so there is nothing to license or attribute. Re-generate with:

    python3 tools/gen_sfx.py      # sound effects (audio/*.wav)
    python3 tools/gen_music.py    # music, ambience, enemy voices, extra UI sounds
                                  # (audio/music, audio/amb, audio/vo, audio/ui; needs scipy + ffmpeg)

The files are part of this project and covered by its license.

## Story voices (audio/voice/)

The spoken lines of Major Okafor, the Source, Colonel Hale and Halden-Voss were generated with
Inworld TTS (model inworld-tts-2, stock voices Bianca, Evelyn, Malcolm, Beatrice and Levi) and then
processed by tools/gen_voices.py (radio, whisper and corruption effects). Inworld's terms assign the
output to the account holder; confirm their terms cover distribution in a commercial game before
release. Re-record and re-process with tools/gen_voices.py (see its header).
Soldier babble is synthesized at play time by view/babble.gd.
