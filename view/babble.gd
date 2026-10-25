extends RefCounted
## Mask babble: a soldier's line as voiced blips through their sealed mask, made at play time from
## the caption text (no recordings). Each syllable is one blip coloured like its vowel; pitch and
## rhythm follow the sentence (questions rise, orders fall). Each class has its own pitch, timbre
## and pace, and each soldier a small pitch offset from their name. The same line by the same
## soldier always sounds the same, so every peer hears what the others hear.
##   var stream := Babble.make("Contact. Here they come.", "trooper", "Reyes", true)

const SR := 22050
const TABLE := 256
const HARMONICS := 24

## Per class: f0 (Hz), source wave, brightness (second formant), syllables per second, pitch
## spread (semitones), mask grille resonance (Hz).
const CLASSES := {
	"trooper": {"f0": 135.0, "wave": "saw", "bright": 1.0, "rate": 9.0, "spread": 3.0, "grille": 1700.0},
	"marksman": {"f0": 118.0, "wave": "tri", "bright": 0.7, "rate": 7.0, "spread": 2.0, "grille": 1500.0},
	"medic": {"f0": 205.0, "wave": "sine", "bright": 0.8, "rate": 9.5, "spread": 4.0, "grille": 2100.0},
	"breacher": {"f0": 92.0, "wave": "square", "bright": 1.1, "rate": 7.5, "spread": 2.0, "grille": 1200.0},
	"hazmat": {"f0": 150.0, "wave": "square", "bright": 0.6, "rate": 8.0, "spread": 3.0, "grille": 900.0},
	"vector": {"f0": 175.0, "wave": "bell", "bright": 1.0, "rate": 10.5, "spread": 5.0, "grille": 2400.0},
	"reaper": {"f0": 105.0, "wave": "saw", "bright": 0.5, "rate": 6.5, "spread": 1.5, "grille": 1100.0},
	"warden": {"f0": 125.0, "wave": "square", "bright": 0.9, "rate": 7.0, "spread": 2.0, "grille": 1400.0},
}
## Vowel -> first and second formant (Hz).
const VOWELS := {"a": Vector2(750, 1250), "e": Vector2(480, 1900), "i": Vector2(330, 2300),
	"o": Vector2(480, 900), "u": Vector2(360, 800), "y": Vector2(350, 2100)}
const PAUSES := {",": 0.14, ".": 0.32, "!": 0.32, "?": 0.32, "-": 0.2, ";": 0.2, ":": 0.2}

static var _tables := {}   # "class:vowel" -> PackedFloat32Array, one cycle


## The class for a caption speaker like "Trooper Reyes" or "MEDIC ADEYEMI", "" if none.
static func class_of(speaker: String) -> String:
	var first := speaker.strip_edges().get_slice(" ", 0).to_lower()
	for k in UnitData.SOLDIERS:
		if str(UnitData.SOLDIERS[k].name).to_lower() == first:
			return k
	return ""


## One blip per vowel group: [vowel, stressed, pause after (s)].
static func syllables(text: String) -> Array:
	var out: Array = []
	var rx := RegEx.create_from_string("[A-Za-z']+|[.,!?;:-]+")
	var vg := RegEx.create_from_string("[aeiouy]+")
	for m in rx.search_all(text):
		var tok := m.get_string()
		if not tok[0].to_lower() in "abcdefghijklmnopqrstuvwxyz'":
			if not out.is_empty():
				out[-1][2] = PAUSES.get(tok[0], 0.1)
			continue
		var low := tok.to_lower()
		var groups := vg.search_all(low)
		var vowels: Array = groups.map(func(g: RegExMatch) -> String: return g.get_string()[0])
		if vowels.is_empty():
			vowels = ["a"]
		if vowels.size() > 1 and low.ends_with("e"):
			vowels.pop_back()
		for i in vowels.size():
			out.append([vowels[i], i == 0 and tok.length() > 3, 0.0])
		out[-1][2] = 0.035
	return out


## The line as a playable stream. `radio` adds the helmet comms click in and out.
static func make(text: String, klass: String, who := "", radio := false) -> AudioStreamWAV:
	var p: Dictionary = CLASSES.get(klass, CLASSES.trooper)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%s|%s" % [klass, who, text])
	var offset := (float(hash(who) % 300) / 100.0 - 1.5) if who != "" else 0.0   # semitones
	var syl := syllables(text)
	var question := text.strip_edges().ends_with("?")
	var buf := PackedFloat32Array()
	if radio:
		buf.append_array(_click(0.6))
		buf.append_array(_chirp(false))
		buf.append_array(_silence(0.02))
	for i in syl.size():
		var s: Array = syl[i]
		var prog := float(i) / maxf(1.0, syl.size() - 1)
		var dur: float = rng.randf_range(0.75, 1.15) / p.rate * (1.25 if s[1] else 1.0)
		if i == syl.size() - 1:
			dur *= 1.5
		var semis: float = rng.randf_range(-p.spread, p.spread) + (2.0 if s[1] else 0.0) + offset
		semis += 3.0 * prog if question else -2.5 * prog * prog
		var f0: float = p.f0 * pow(2.0, semis / 12.0)
		var glide := pow(2.0, rng.randf_range(-1.2, 0.6) / 12.0)
		buf.append_array(_blip(_table(klass, s[0]), f0, glide, dur, 1.0 if s[1] else 0.8, rng.randf() < 0.55, rng))
		if s[2] > 0.0:
			buf.append_array(_silence(s[2]))
	if radio:
		buf.append_array(_silence(0.02))
		buf.append_array(_chirp(true))
		buf.append_array(_click(-0.5))
	return _to_stream(buf)


## One cycle of the class's wave through the vowel's formants and the mask grille.
static func _table(klass: String, vowel: String) -> PackedFloat32Array:
	var key := "%s:%s" % [klass, vowel]
	if _tables.has(key):
		return _tables[key]
	var p: Dictionary = CLASSES.get(klass, CLASSES.trooper)
	var fm: Vector2 = VOWELS.get(vowel, Vector2(500, 1500))
	var amps := PackedFloat32Array()
	for k in range(1, HARMONICS + 1):
		var f: float = p.f0 * k
		var src := 1.0 / k
		match p.wave:
			"square": src = 1.0 / k if k % 2 == 1 else 0.15 / k
			"tri": src = 1.0 / (k * k) if k % 2 == 1 else 0.0
			"sine": src = [1.0, 0.5, 0.25, 0.1][k - 1] if k <= 4 else 0.0
			"bell": src = 1.0 / k * (1.4 if k % 3 == 0 else 0.7)
		var g := 0.15 + _peak(f, fm.x, fm.x * 0.25) + 0.6 * float(p.bright) * _peak(f, fm.y, fm.y * 0.15) \
			+ 0.8 * _peak(f, p.grille, 300.0) + 0.4 * _peak(f, p.grille * 2.3, 500.0)
		amps.append(src * g)
	var t := PackedFloat32Array()
	t.resize(TABLE)
	var peak := 0.0
	for i in TABLE:
		var v := 0.0
		for k in HARMONICS:
			v += amps[k] * sin(TAU * (k + 1) * i / TABLE)
		t[i] = v
		peak = maxf(peak, absf(v))
	for i in TABLE:
		t[i] /= maxf(peak, 0.0001)
	_tables[key] = t
	return t


static func _peak(f: float, centre: float, width: float) -> float:
	var d := (f - centre) / width
	return 1.0 / (1.0 + d * d)


static func _blip(table: PackedFloat32Array, f0: float, glide: float, dur: float, amp: float, tick: bool,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var a := int(0.006 * SR)
	var rel := int(minf(0.04, dur * 0.4) * SR)
	var ph := 0.0
	var tk := int(0.012 * SR) if tick else 0
	var last := 0.0
	for i in n:
		var f := f0 * lerpf(1.0, glide, float(i) / n)
		ph = fmod(ph + f * TABLE / SR, TABLE)
		var j := int(ph)
		var v := lerpf(table[j], table[(j + 1) % TABLE], ph - j)
		var e := 1.0
		if i < a:
			e = float(i) / a
		elif i > n - rel:
			e = pow(float(n - i) / rel, 1.5)
		if i < tk:   # consonant: a short high-passed noise tick
			var w := rng.randf_range(-1.0, 1.0)
			v += (w - last) * 0.35 * (1.0 - float(i) / tk)
			last = w
		out[i] = clampf(v * e * amp * 0.7, -1.0, 1.0)
	return out


static func _silence(d: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(d * SR))
	return out


static func _click(v: float) -> PackedFloat32Array:
	var out := _silence(0.01)
	out[0] = v
	out[30] = -v * 0.6
	return out


## The comms chirp: a fast falling sweep on key-up, rising on release.
static func _chirp(release: bool) -> PackedFloat32Array:
	var n := int(0.04 * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / SR
		out[i] = sin(TAU * (2200.0 - 9000.0 * t) * t) * 0.12 * (1.0 - float(i) / n)
	if release:
		out.reverse()
	return out


static func _to_stream(buf: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 30000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = SR
	s.stereo = false
	s.data = bytes
	return s
