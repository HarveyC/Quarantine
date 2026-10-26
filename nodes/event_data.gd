class_name EventData
extends RefCounted
## The text events of a run, as data. EventRules runs them. OWNER: nodes workstream.
##
## Event fields:
##   title, text          the scene, shown to everyone
##   acts                 acts it can appear in (default all)
##   weight               {act: weight}, default 1 (act 1 leans on the low-stakes ones)
##   requires             {"infected_soldier": n} some present soldier is at n+ Infection;
##                        {"wounded_soldier": true} some present soldier is below max HP
##   subject              "most_infected" | "most_wounded": the soldier the event is about,
##                        named as {subject} in text; an "owner" step is decided by its owner
##   start                first step id
##   steps                step id -> step
##
## Step fields:
##   kind      "vote"       every present player votes, majority wins, the host breaks a tie
##             "secret"     every player picks privately; picks resolve together
##             "per_player" every player picks for their own soldiers; resolves at once
##             "volunteer"  the first player to claim it does it (with one of their soldiers)
##             "owner"      only the owner of the subject decides
##   prompt    the question
##   options   [{id, label, desc, requires?, target?, target_requires?, effects?, outcome?, next?, default?}]
##             requires: {"supplies": n, "intel": n, "waived_by": class} (waived_by drops the cost
##                       requirement when that class is in the squad; pair it with unless_class on the effect)
##             target "own_soldier": the chooser picks one of their own soldiers ({soldier} in text)
##             target_requires: {"has_mutation": true, "infection_at_least": n, "infection_below": n,
##                              "graft_ready": true (Rank 3+ with a free graft slot, from Act 2)}
##             default: picked for players who run out the timer (otherwise the last option)
##   next      step after this one ("" or missing = the event ends); an option's next wins
##   nobody    volunteer only: {"effects", "outcome", "next"} when every player passes
##   unanimous secret only: {"option", "effects", "outcome", "per_player"} applied when every
##             player picked that option (per_player runs the effects once per player's pick)
##   generate  per_player only: {"items": n, "rarity": r}: each player picks 1 of n drawn items,
##             equipped on a soldier they choose
##   skip_if_class  {"class", "to", "outcome"}: jump straight to another step when the squad has that class
##
## Effects: {"op": ..., ...}
##   supplies / intel / outbreak  {amount, unless_class?}
##   infection {amount, who}  heal_pct {pct, who}  hurt_pct {pct, who}
##   mutation {who}  remove_mutation {who, serum}  perk_pick {who}
##   bloom_graft {who}           a Bloom graft in a random free slot, with its Infection (Grafts)
##   serum {samples, to: "player"|"least_serum"}
##   recruit {count, infection, to: "player"|"fewest", carrier}   (carrier: one of them is a hidden carrier)
##   item {count, rarity, who}   (drawn and equipped on that soldier)
##   gun {rarity, who}           an alternate gun for that soldier's class, carried at once
##   modifier {key, value}       next-fight/map effects, see docs/ARCHITECTURE.md
##   mark {key, who}             adds the soldier's id to the list modifiers[key]
##   sit_out {who}               the soldier misses the next fight (held at the Checkpoint)
##   fight {objective, ambush?, small?}  the event ends in a fight (modifiers.pending_fight);
##                               small = one enemy fewer
##   send_home {who}             the soldier leaves the run; their owner gets a recruit with a perk pick
##   chance {p, then, else}      if_infected {at_least, who, then, else}
##   who: "soldier" (the chooser's pick), "subject", "all" (every present soldier)

const EVENTS := {
	"checkpoint": {
		"title": "Checkpoint",
		"acts": [1, 2],
		"weight": {1: 3},
		"text": "A Cordon gate, floodlit and sandbagged. Two guards in rebreathers keep their rifles on the squad's glow. \"Lanterns don't come back through without papers. Or a bribe. Or a blood test, if you're feeling honest.\"",
		"start": "gate",
		"steps": {
			"gate": {
				"kind": "vote",
				"prompt": "How do you get through?",
				"options": [
					{"id": "pay", "label": "Pay them off", "desc": "-30 Supplies", "requires": {"supplies": 30},
						"effects": [{"op": "supplies", "amount": -30}],
						"outcome": "The crate changes hands. The gate grinds open and nobody looks anyone in the eye."},
					{"id": "scan", "label": "Take the blood scan", "desc": "A volunteer is scanned. If Exposed or worse they're held for a fight, but the guards trade 2 Intel", "next": "scan"},
					{"id": "force", "label": "Force the gate", "desc": "Fight your way through (Extract)",
						"effects": [{"op": "fight", "objective": "extract"}],
						"outcome": "Someone kills the floodlights. The guards start shouting into their radios."},
				],
			},
			"scan": {
				"kind": "volunteer",
				"prompt": "Somebody has to roll up a sleeve.",
				"options": [
					{"id": "volunteer", "label": "I'll do it", "desc": "Pick one of your soldiers", "target": "own_soldier",
						"effects": [{"op": "if_infected", "at_least": 25, "who": "soldier",
							"then": [{"op": "sit_out", "who": "soldier"}, {"op": "intel", "amount": 2}],
							"else": []}],
						"outcome": "{soldier} holds out an arm. The scanner hums, then clicks."},
				],
				"nobody": {"next": "gate_again", "outcome": "Nobody moves. The guard shrugs and taps the gate controls."},
			},
			"gate_again": {
				"kind": "vote",
				"prompt": "Papers, bribe or bullets, then.",
				"options": [
					{"id": "pay", "label": "Pay them off", "desc": "-30 Supplies", "requires": {"supplies": 30},
						"effects": [{"op": "supplies", "amount": -30}], "outcome": "The crate changes hands. The gate grinds open."},
					{"id": "force", "label": "Force the gate", "desc": "Fight your way through (Extract)",
						"effects": [{"op": "fight", "objective": "extract"}], "outcome": "Someone kills the floodlights."},
				],
			},
		},
	},
	"last_broadcast": {
		"title": "Last broadcast",
		"acts": [1, 2],
		"weight": {1: 3},
		"text": "A relay mast on a grain silo, still drawing power from somewhere. The speaker loops an evacuation order from eleven days ago. Below it, in the dark, a lot of people are still listening.",
		"start": "mast",
		"steps": {
			"mast": {
				"kind": "vote",
				"prompt": "What do you do with the mast?",
				"options": [
					{"id": "broadcast", "label": "Broadcast a safe route", "desc": "Outbreak -2, but the next fight has +1 enemy (the Bloom hears it too)",
						"effects": [{"op": "outbreak", "amount": -2}, {"op": "modifier", "key": "extra_enemies", "value": 1}],
						"outcome": "Your medic reads out the route twice, slowly. Somewhere east, lights start moving. So does something else."},
					{"id": "strip", "label": "Strip it for parts", "desc": "+20 Supplies",
						"effects": [{"op": "supplies", "amount": 20}],
						"outcome": "The loop cuts out mid-sentence. The batteries are worth it. Nobody says anything for a while."},
				],
			},
		},
	},
	"the_trial": {
		"title": "The trial",
		"acts": [1, 2, 3],
		"text": "A Halden-Voss field lab, abandoned in a hurry. One fridge still runs: a rack of teal vials labelled CARRIER STRAIN / REV. 9. A note taped to the door: \"It works. God help us, it works.\"",
		"start": "offer",
		"steps": {
			"offer": {
				"kind": "secret",
				"prompt": "Do any of your soldiers take a shot? Everyone decides in private.",
				"options": [
					{"id": "take", "label": "Take a shot", "desc": "That soldier gains a random mutation and +15 Infection", "target": "own_soldier",
						"effects": [{"op": "mutation", "who": "soldier"}, {"op": "infection", "amount": 15, "who": "soldier"}],
						"outcome": "{soldier} takes the shot. Their veins light up like a city at night."},
					{"id": "refuse", "label": "Leave them on the rack", "desc": "Nothing happens", "default": true},
				],
				"unanimous": {"option": "take", "effects": [{"op": "serum", "samples": 2, "to": "least_serum"}],
					"outcome": "Every hand went up. Under the rack, a sealed case: two Serum samples, \"for trial participants\"."},
			},
		},
	},
	"supply_cache": {
		"title": "Supply cache",
		"acts": [1, 2, 3],
		"text": "A Cordon supply drop, chute still tangled on a lamppost. One crate. Everyone's hands are on it at once, and nobody is letting go first.",
		"start": "crate",
		"steps": {
			"crate": {
				"kind": "secret",
				"prompt": "Share it or grab it? If everyone shares, everyone gets something. Grabbers get double, and sharers get nothing.",
				"options": [
					{"id": "share", "label": "Share", "desc": "If everyone shares, one of your soldiers gets an item", "target": "own_soldier", "default": true},
					{"id": "grab", "label": "Grab", "desc": "Two items for one of your soldiers, and sharers get nothing", "target": "own_soldier",
						"effects": [{"op": "item", "count": 2, "rarity": "common", "who": "soldier"}],
						"outcome": "{soldier} gets there first and fills both arms."},
				],
				"unanimous": {"option": "share", "per_player": true,
					"effects": [{"op": "item", "count": 1, "rarity": "uncommon", "who": "soldier"}],
					"outcome": "The crate gets split clean, down the middle and down again. Good kit, too."},
			},
		},
	},
	"bitten": {
		"title": "Bitten",
		"acts": [1, 2, 3],
		"text": "A colonist in a torn grain-co jacket stumbles out of a stairwell with her hands up. The bite on her forearm is fresh, already threaded with teal. \"I can shoot. I can carry. Please don't leave me here.\"",
		"start": "choice",
		"steps": {
			"choice": {
				"kind": "vote",
				"prompt": "What do you do with her?",
				"options": [
					{"id": "take", "label": "Take her with you", "desc": "A recruit for the player with the smallest reserve, starting at 40 Infection",
						"effects": [{"op": "recruit", "count": 1, "infection": 40, "to": "fewest"}],
						"outcome": "Someone hands her a sidearm. She doesn't ask what the glow means. She already knows."},
					{"id": "mercy", "label": "Give her a clean end", "desc": "Nothing",
						"outcome": "One shot. Quick. The squad moves on and the radio stays quiet for a long time."},
					{"id": "leave", "label": "Leave her", "desc": "Outbreak +1",
						"effects": [{"op": "outbreak", "amount": 1}],
						"outcome": "You leave her in the stairwell. By the time you reach the corner, she has stopped calling after you."},
				],
			},
		},
	},
	"spore_bloom": {
		"title": "Spore bloom",
		"acts": [1, 2, 3],
		"text": "The underpass is choked wall to wall with Bloom, pulsing slowly like it's breathing. Spores hang in the torchlight. Through the haze you can see crates someone abandoned on the far side.",
		"start": "choice",
		"steps": {
			"choice": {
				"kind": "vote",
				"prompt": "How do you get past?",
				"options": [
					{"id": "burn", "label": "Burn it out", "desc": "Free with a Hazmat, otherwise -30 Supplies of fuel",
						"requires": {"supplies": 30, "waived_by": "hazmat"},
						"effects": [{"op": "supplies", "amount": -30, "unless_class": "hazmat"}],
						"outcome": "The Bloom screams as it burns. It shouldn't be able to scream."},
					{"id": "push", "label": "Push through", "desc": "Every soldier +10 Infection, +20 Supplies from the crates",
						"effects": [{"op": "infection", "amount": 10, "who": "all"}, {"op": "supplies", "amount": 20}],
						"outcome": "Masks up, heads down. The spores settle on everyone's skin like warm snow."},
					{"id": "detour", "label": "Find another way", "desc": "Outbreak +1",
						"effects": [{"op": "outbreak", "amount": 1}],
						"outcome": "Three hours through the sewers. Behind you, the Bloom spreads into the street."},
				],
			},
		},
	},
	"whispers": {
		"title": "Whispers",
		"acts": [1, 2, 3],
		"requires": {"infected_soldier": 50},
		"subject": "most_infected",
		"text": "{subject} stops dead in the middle of the road. They can hear it now, under the radio static: a voice from very far down, warm and patient. It knows their name. It knows what they want.",
		"start": "choice",
		"steps": {
			"choice": {
				"kind": "owner",
				"prompt": "{subject} hears the Source. Does {subject} listen?",
				"options": [
					{"id": "listen", "label": "Listen", "desc": "{subject} gains a mutation and +10 Infection",
						"effects": [{"op": "mutation", "who": "subject"}, {"op": "infection", "amount": 10, "who": "subject"}],
						"outcome": "{subject} closes their eyes and lets it in. When they open them, something new looks out."},
					{"id": "fight", "label": "Fight it", "desc": "{subject} loses 1 action on the first turn of the next fight", "default": true,
						"effects": [{"op": "mark", "key": "first_turn_action_loss", "who": "subject"}],
						"outcome": "{subject} bites down until they taste blood. The voice goes quiet. It isn't gone."},
				],
			},
		},
	},
	"weapons_cache": {   # Entered from the Weapons cache map node, never drawn as a random event.
		"title": "Weapons cache",
		"acts": [1, 2, 3],
		"weight": {1: 0, 2: 0, 3: 0},
		"text": "A Cordon armory, shuttered in the first hour and never reopened. The racks are still dressed. Everything has been waiting for someone to sign for it.",
		"start": "open",
		"steps": {
			"open": {
				"kind": "vote",
				"prompt": "Break the shutter?",
				"options": [
					{"id": "open", "label": "Open the cache", "desc": "Every soldier takes a gun: their class gun if they are still on the sidearm, else a new one",
						"effects": [{"op": "gun", "rarity": "uncommon", "who": "all"}],
						"outcome": "The shutter screams up on its rails. Everyone signs for something."},
				],
			},
		},
	},
	"arms_locker": {
		"title": "Cordon arms locker",
		"acts": [1, 2, 3],
		"text": "A Cordon patrol made its last stand in a bus shelter. Their arms locker is still chained to the frame, and something has grown over the padlock in pale, warm ropes.",
		"start": "locker",
		"steps": {
			"locker": {
				"kind": "volunteer",
				"prompt": "The guns inside are good ones. Someone has to get through the growth first.",
				"options": [
					{"id": "cut", "label": "Cut it open", "desc": "One of your soldiers gains 10 Infection and takes a new gun for their class",
						"target": "own_soldier",
						"effects": [{"op": "infection", "amount": 10, "who": "soldier"}, {"op": "gun", "rarity": "uncommon", "who": "soldier"}],
						"outcome": "{soldier} hacks through the ropes. They bleed something thin and bright, and the locker swings open."},
					{"id": "burn", "label": "Burn it off", "desc": "Free with a Hazmat, otherwise -20 Supplies of fuel. One of your soldiers takes a new gun",
						"target": "own_soldier", "requires": {"supplies": 20, "waived_by": "hazmat"},
						"effects": [{"op": "supplies", "amount": -20, "unless_class": "hazmat"}, {"op": "gun", "rarity": "uncommon", "who": "soldier"}],
						"outcome": "The growth curls back from the flame. {soldier} takes their pick of what's inside."},
				],
				"nobody": {"outcome": "Nobody touches it. The ropes on the lock pulse once as you leave."},
			},
		},
	},
	"sealed_armoury": {
		"title": "Sealed armoury",
		"acts": [1, 2, 3],
		"text": "A militia armoury, blast door down and the keypad fried. Through the slit window: racks of kit nobody has touched since the wall went up.",
		"start": "door",
		"steps": {
			"door": {
				"kind": "volunteer",
				"prompt": "Somebody has to force the door. It's going to hurt.",
				"skip_if_class": {"class": "breacher", "to": "loot",
					"outcome": "Your Breacher reads the hinges, sets a charge the size of a matchbox, and the door folds inward."},
				"options": [
					{"id": "force", "label": "Force it", "desc": "One of your soldiers loses 30% of their health", "target": "own_soldier",
						"effects": [{"op": "hurt_pct", "pct": 30, "who": "soldier"}],
						"outcome": "{soldier} gets a bar into the seal and heaves until something gives. Not all of it was the door.", "next": "loot"},
				],
				"nobody": {"outcome": "Nobody fancies it. You leave the armoury to the Bloom."},
			},
			"loot": {
				"kind": "per_player",
				"prompt": "Every player takes one of two items for one of their soldiers.",
				"generate": {"items": 2, "rarity": "uncommon"},
				"options": [],
			},
		},
	},
	"back_alley_medic": {
		"title": "Back-alley medic",
		"acts": [1, 2, 3],
		"text": "A deserter in a stained Cordon medic's smock runs a clinic out of a laundromat. Cots between the dryers. \"I purge, I buy, I don't ask. Payment up front.\"",
		"start": "clinic",
		"steps": {
			"clinic": {
				"kind": "per_player",
				"prompt": "Each player can treat or trade one of their soldiers.",
				"options": [
					{"id": "purge", "label": "Purge a soldier", "desc": "-30 Infection for 15 Supplies", "target": "own_soldier",
						"requires": {"supplies": 15}, "target_requires": {"infection_at_least": 1},
						"effects": [{"op": "supplies", "amount": -15}, {"op": "infection", "amount": -30, "who": "soldier"}],
						"outcome": "{soldier} lies down between the dryers. The purge burns like cold fire."},
					{"id": "sell", "label": "Sell a mutation", "desc": "Remove a soldier's newest mutation for 1 Serum sample", "target": "own_soldier",
						"target_requires": {"has_mutation": true},
						"effects": [{"op": "remove_mutation", "who": "soldier", "serum": 1}],
						"outcome": "The medic cuts something out of {soldier} and seals it in a jar. Nobody asks who buys these."},
					{"id": "nothing", "label": "Walk on", "desc": "Nothing", "default": true},
				],
			},
		},
	},
	"air_support": {
		"title": "Air support",
		"acts": [1, 2, 3],
		"text": "Major Okafor on the command net, voice clipped: \"Lantern, I can give you one gunship pass. One. In return, Command wants eyes on that nest on your flank. No arguments.\"",
		"start": "choice",
		"steps": {
			"choice": {
				"kind": "vote",
				"prompt": "Take the strike?",
				"options": [
					{"id": "accept", "label": "Accept", "desc": "The next fight starts with 2 enemies dead, but the next node must be an Infested nest if one is reachable",
						"effects": [{"op": "modifier", "key": "enemies_dead_at_start", "value": 2}, {"op": "modifier", "key": "force_nest_next", "value": true}],
						"outcome": "\"Copy, Lantern. Gunship inbound. Don't make me regret this.\""},
					{"id": "decline", "label": "Decline", "desc": "Nothing", "default": true,
						"outcome": "\"Your funeral, Lantern. Okafor out.\""},
				],
			},
		},
	},
	"stragglers": {
		"title": "Stragglers",
		"acts": [1, 2, 3],
		"text": "Two Cordon troopers from a unit that was wiped out last week, hollow-eyed and low on ammo. They want to join up. One of them keeps his collar buttoned high, even in the heat.",
		"start": "choice",
		"steps": {
			"choice": {
				"kind": "vote",
				"prompt": "Take them in?",
				"options": [
					{"id": "take", "label": "Take them in", "desc": "A recruit each for the two players with the smallest reserves. One is a hidden carrier who may Lapse in their first fight",
						"effects": [{"op": "recruit", "count": 2, "infection": 0, "to": "fewest", "carrier": true}],
						"outcome": "They fall in at the back. Neither of them sleeps much."},
					{"id": "refuse", "label": "Turn them away", "desc": "Nothing", "default": true,
						"outcome": "You point them at the wall. They don't argue. They just watch you go."},
				],
			},
		},
	},
	"the_bridge": {
		"title": "The bridge",
		"acts": [1, 2, 3],
		"text": "The last crossing over the canal, behind you now. Bloom is already creeping along the girders toward your side. The demolition charges on the pylons are still armed.",
		"start": "choice",
		"steps": {
			"choice": {
				"kind": "vote",
				"prompt": "Blow the bridge?",
				"options": [
					{"id": "blow", "label": "Blow it", "desc": "Outbreak -3, but this act's map loses one column of nodes",
						"effects": [{"op": "outbreak", "amount": -3}, {"op": "modifier", "key": "remove_column", "value": true}],
						"outcome": "The bridge goes down in a slow, groaning fold. The Bloom on the far side keeps reaching for a while."},
					{"id": "leave", "label": "Leave it standing", "desc": "Nothing", "default": true,
						"outcome": "Somebody else might need it. Somebody else might not be a somebody by then."},
				],
			},
		},
	},
	"field_chapel": {
		"title": "Field chapel",
		"acts": [1, 2, 3],
		"weight": {1: 3},
		"text": "A colony chapel with the doors still barred from the inside. Candles long burnt down. It's the first quiet room in days, and the pews are untouched.",
		"start": "choice",
		"steps": {
			"choice": {
				"kind": "vote",
				"prompt": "Rest, or search the place?",
				"options": [
					{"id": "rest", "label": "Rest", "desc": "Every soldier heals 20% of max HP",
						"effects": [{"op": "heal_pct", "pct": 20, "who": "all"}],
						"outcome": "An hour of sleep on hard wood. It's the best hour any of you have had since the wall."},
					{"id": "search", "label": "Search it", "desc": "+1 Intel, 50% chance of a small ambush",
						"effects": [{"op": "intel", "amount": 1}, {"op": "chance", "p": 0.5,
							"then": [{"op": "fight", "objective": "ambush", "ambush": true, "small": true}],
							"else": []}],
						"outcome": "Behind the altar, a Halden-Voss courier bag. Inside, a survey log that mentions \"the Lattice\" a year before the drilling."},
				],
			},
		},
	},
	"last_seat": {
		"title": "Last seat",
		"acts": [1, 2, 3],
		"requires": {"wounded_soldier": true},
		"subject": "most_wounded",
		"text": "A Cordon dropship on a rooftop pad, rotors already turning. The loadmaster holds up one finger. One seat left, and {subject} can barely stand.",
		"start": "offer",
		"steps": {
			"offer": {
				"kind": "owner",
				"prompt": "Does {subject} take the seat?",
				"options": [
					{"id": "offer", "label": "Put {subject} on the flight", "desc": "The squad votes on it next", "next": "vote"},
					{"id": "stay", "label": "{subject} stays", "desc": "A civilian gets the seat. Outbreak -1", "default": true,
						"effects": [{"op": "outbreak", "amount": -1}],
						"outcome": "{subject} waves the loadmaster off. A kid with a grain-co badge climbs aboard instead."},
				],
			},
			"vote": {
				"kind": "vote",
				"prompt": "Send {subject} home?",
				"options": [
					{"id": "send", "label": "Send them home", "desc": "{subject} leaves the run. Their owner gets a fresh recruit with a perk pick",
						"effects": [{"op": "send_home", "who": "subject"}],
						"outcome": "{subject} is strapped in before they can argue. The dropship lifts, and the squad is one shorter."},
					{"id": "civilian", "label": "Give it to a civilian", "desc": "Outbreak -1", "default": true,
						"effects": [{"op": "outbreak", "amount": -1}],
						"outcome": "A kid with a grain-co badge climbs aboard. {subject} watches the lights go."},
				],
			},
		},
	},
	"source_signal": {
		"title": "The Source's signal",
		"acts": [3],
		"text": "Every radio in the squad wakes at once. No voice, just a pattern, repeating from the bottom of the Bore, patient as a heartbeat. It is not a distress call. It sounds like an invitation.",
		"start": "choice",
		"steps": {
			"choice": {
				"kind": "vote",
				"prompt": "What do you do with the signal?",
				"options": [
					{"id": "decode", "label": "Decode it", "desc": "Spend 2 Intel: the boss starts with 20% less health", "requires": {"intel": 2},
						"effects": [{"op": "intel", "amount": -2}, {"op": "modifier", "key": "boss_health_mult", "value": 0.8}],
						"outcome": "It's a map of the Source, drawn from the inside. Someone down there wanted you to find the soft parts."},
					{"id": "jam", "label": "Jam it", "desc": "Outbreak -1",
						"effects": [{"op": "outbreak", "amount": -1}],
						"outcome": "White noise floods the band. Somewhere below, something notices."},
					{"id": "ignore", "label": "Ignore it", "desc": "Nothing", "default": true,
						"outcome": "You turn the radios off. The pattern keeps going in everyone's head anyway."},
				],
			},
		},
	},
	# ---------------------------------------------------------------- Port Ardent (act 2)
	"recovery_team": {
		"title": "Recovery team",
		"acts": [2, 3],
		"weight": {2: 2},
		"requires": {"infected_soldier": 25},
		"subject": "most_infected",
		"text": "Four figures in white Halden-Voss hazard suits, logo polished, rifles slung like they've never used them. Their lead lowers a cold-box. \"We pay for samples. Fresh ones. Your {subject} is glowing like a beacon, and we only need a pint.\"",
		"start": "deal",
		"steps": {
			"deal": {
				"kind": "owner",
				"prompt": "Does {subject} give the Recovery team a sample?",
				"options": [
					{"id": "sell", "label": "Sell a sample", "desc": "{subject} loses 20 Infection and 20% of their HP; +30 Supplies",
						"effects": [{"op": "infection", "amount": -20, "who": "subject"}, {"op": "hurt_pct", "pct": 20, "who": "subject"},
							{"op": "supplies", "amount": 30}],
						"outcome": "The needle is very large and very cold. The Recovery lead seals the vial like it's a jewel."},
					{"id": "refuse", "label": "Refuse", "desc": "The squad votes on what to do about them", "default": true, "next": "after"},
				],
			},
			"after": {
				"kind": "vote",
				"prompt": "They won't take no for long. Let them walk, or take their kit?",
				"options": [
					{"id": "walk", "label": "Let them walk", "desc": "Nothing", "default": true,
						"outcome": "They back off with their hands where you can see them. Their drone follows the squad for the next mile."},
					{"id": "rob", "label": "Take their kit", "desc": "Fight them for it (Hold); +1 Intel from their datapad",
						"effects": [{"op": "intel", "amount": 1}, {"op": "fight", "objective": "hold"}],
						"outcome": "The lead grabs for his radio. More white suits are already coming up the street."},
				],
			},
		},
	},
	"choir_stall": {
		"title": "Choir stall",
		"acts": [2, 3],
		"text": "A market stall under a tram bridge, strung with teal lanterns that aren't lanterns. The woman behind it hums with her mouth closed. Jars line the shelves, each holding something that moves. \"The Bloom gives. The Bloom takes back. Trade with us, Lantern.\"",
		"start": "trade",
		"steps": {
			"trade": {
				"kind": "per_player",
				"prompt": "Each player can trade with the Choir for one of their soldiers.",
				"options": [
					{"id": "graft", "label": "Take a graft", "desc": "A random mutation and +10 Infection", "target": "own_soldier",
						"effects": [{"op": "mutation", "who": "soldier"}, {"op": "infection", "amount": 10, "who": "soldier"}],
						"outcome": "She presses a jar against {soldier}'s wrist. Whatever was inside isn't in the jar any more."},
					{"id": "root", "label": "Let it take root", "desc": "A Bloom graft for a free body slot. It never leaves", "target": "own_soldier",
						"target_requires": {"graft_ready": true},
						"effects": [{"op": "bloom_graft", "who": "soldier"}],
						"outcome": "She hums a note too low to hear and lays her hand flat on {soldier}. Something under the plate carrier answers."},
					{"id": "sell", "label": "Sell a mutation", "desc": "Remove the newest mutation for 1 Serum sample and 15 Supplies", "target": "own_soldier",
						"target_requires": {"has_mutation": true},
						"effects": [{"op": "remove_mutation", "who": "soldier", "serum": 1}, {"op": "supplies", "amount": 15}],
						"outcome": "The Choir woman draws it out of {soldier} with her bare hands and kisses the jar shut."},
					{"id": "nothing", "label": "Walk on", "desc": "Nothing", "default": true},
				],
			},
		},
	},
	"flooded_metro": {
		"title": "Flooded metro",
		"acts": [2],
		"weight": {2: 2},
		"text": "The Ardent Line runs under the harbour, and the harbour has come in. Black water up to the platform edge, a tram roof just breaking the surface. Something big turns over in the dark at the far end.",
		"start": "choice",
		"steps": {
			"choice": {
				"kind": "vote",
				"prompt": "How do you cross?",
				"options": [
					{"id": "swim", "label": "Swim the tunnel", "desc": "Every soldier loses 15% HP; +1 Intel from a drowned courier",
						"effects": [{"op": "hurt_pct", "pct": 15, "who": "all"}, {"op": "intel", "amount": 1}],
						"outcome": "Cold enough to stop your heart. Halfway across, a Halden-Voss courier floats past, case still cuffed to his wrist."},
					{"id": "roof", "label": "Run the tram roofs", "desc": "50% chance of an ambush from the water",
						"effects": [{"op": "chance", "p": 0.5,
							"then": [{"op": "fight", "objective": "extract", "ambush": true, "small": true}],
							"else": []}],
						"outcome": "Boots on wet steel, one roof to the next. The water behind you starts to move."},
					{"id": "surface", "label": "Go round by the streets", "desc": "Outbreak +1", "default": true,
						"effects": [{"op": "outbreak", "amount": 1}],
						"outcome": "An hour lost in the backstreets. The Bloom uses every minute of it."},
				],
			},
		},
	},
	"lab_terminal": {
		"title": "Lab terminal",
		"acts": [2],
		"weight": {2: 2},
		"text": "Halden-Voss Building 4, research floor. Every screen is dead but one, logged in as Dr. Renn, cursor blinking in a folder named LATTICE / PRE-CONTACT. The building's security system is still armed and very patient.",
		"start": "choice",
		"steps": {
			"choice": {
				"kind": "vote",
				"prompt": "What do you do with the terminal?",
				"options": [
					{"id": "download", "label": "Download everything", "desc": "+2 Intel, 50% chance the alarm brings a fight",
						"effects": [{"op": "intel", "amount": 2}, {"op": "chance", "p": 0.5,
							"then": [{"op": "fight", "objective": "skirmish", "ambush": true}],
							"else": []}],
						"outcome": "The drive fills slowly. They knew the fungus was aware before the first drill went in. They drilled anyway."},
					{"id": "skim", "label": "Skim it and go", "desc": "+1 Intel", "default": true,
						"effects": [{"op": "intel", "amount": 1}],
						"outcome": "You photograph the first page and leave the rest. Nobody wants to read the rest."},
					{"id": "wipe", "label": "Wipe the servers", "desc": "Outbreak -1: nobody else gets to weaponise this",
						"effects": [{"op": "outbreak", "amount": -1}],
						"outcome": "Someone pulls the drives and drops them in a sink of acid. Somewhere, an executive's phone buzzes."},
				],
			},
		},
	},
	"okafor_orders": {
		"title": "Orders from Okafor",
		"acts": [2, 3],
		"text": "\"Lantern, Okafor. I have three hundred civilians walking to the harbour and nothing between them and the Bloom but you. Hold the crossing until the ferries clear. That's not a request.\"",
		"start": "choice",
		"steps": {
			"choice": {
				"kind": "vote",
				"prompt": "Hold the crossing?",
				"options": [
					{"id": "hold", "label": "Hold it", "desc": "Fight now (Hold): Outbreak -2 and +20 Supplies from Command",
						"effects": [{"op": "outbreak", "amount": -2}, {"op": "supplies", "amount": 20}, {"op": "fight", "objective": "hold"}],
						"outcome": "\"Good. The ferries are loading. Don't let anything through.\""},
					{"id": "refuse", "label": "Keep moving", "desc": "Outbreak +2", "default": true,
						"effects": [{"op": "outbreak", "amount": 2}],
						"outcome": "Okafor doesn't answer. Later, on the wind, you hear the ferry horns stop."},
				],
			},
		},
	},
	"harbour_ferry": {
		"title": "The last ferry",
		"acts": [2],
		"text": "A rust-streaked ferry at the harbour wall, engines coughing, deck packed with colonists. The captain waves you down: he can't cast off without a gunner on the bridge, and his own walked into the water this morning.",
		"start": "choice",
		"steps": {
			"choice": {
				"kind": "volunteer",
				"prompt": "Somebody rides the ferry out and back. They'll miss the next fight.",
				"options": [
					{"id": "ride", "label": "I'll ride it", "desc": "One of your soldiers sits out the next fight; Outbreak -2 and they heal fully",
						"target": "own_soldier",
						"effects": [{"op": "sit_out", "who": "soldier"}, {"op": "outbreak", "amount": -2}, {"op": "heal_pct", "pct": 100, "who": "soldier"}],
						"outcome": "{soldier} takes the bridge gun. The ferry pulls away, low in the water and very quiet."},
				],
				"nobody": {"next": "supplies", "outcome": "Nobody can spare the time. The captain spits into the harbour."},
			},
			"supplies": {
				"kind": "vote",
				"prompt": "Give them something for the crossing?",
				"options": [
					{"id": "give", "label": "Give them supplies", "desc": "-20 Supplies, Outbreak -1", "requires": {"supplies": 20},
						"effects": [{"op": "supplies", "amount": -20}, {"op": "outbreak", "amount": -1}],
						"outcome": "Two crates of rations go up the gangway. The captain salutes, badly."},
					{"id": "nothing", "label": "Nothing to spare", "desc": "Nothing", "default": true,
						"outcome": "You watch the ferry go. You don't watch long enough to see if it makes it."},
				],
			},
		},
	},
	"black_market": {
		"title": "Black market",
		"acts": [2],
		"weight": {2: 2},
		"text": "A parking garage under the Exchange, lit by work lamps and a generator. Cordon deserters, dock gangers and one very calm Halden-Voss clerk sell anything that fell off anything. Prices are steep. Questions are steeper.",
		"start": "buy",
		"steps": {
			"buy": {
				"kind": "per_player",
				"prompt": "Each player can buy one piece of kit for one of their soldiers.",
				"options": [
					{"id": "buy", "label": "Buy a crate", "desc": "-30 Supplies: an Uncommon item", "target": "own_soldier", "requires": {"supplies": 30},
						"effects": [{"op": "supplies", "amount": -30}, {"op": "item", "count": 1, "rarity": "uncommon", "who": "soldier"}],
						"outcome": "No receipt. The crate is lighter than it should be, but what's inside works."},
					{"id": "intel", "label": "Buy a rumour", "desc": "-15 Supplies: +1 Intel", "requires": {"supplies": 15},
						"effects": [{"op": "supplies", "amount": -15}, {"op": "intel", "amount": 1}],
						"outcome": "The clerk writes a grid reference on a napkin and eats the napkin."},
					{"id": "nothing", "label": "Just looking", "desc": "Nothing", "default": true},
				],
			},
		},
	},
	"quarantine_ward": {
		"title": "Quarantine ward",
		"acts": [2],
		"text": "St. Brigid's, sixth floor, sealed with tape and prayers. The ward is full of patients in restraints, all asleep, all glowing faintly. The pharmacy at the end of the corridor is still locked. A nurse is still on shift.",
		"start": "choice",
		"steps": {
			"choice": {
				"kind": "vote",
				"prompt": "What do you take from St. Brigid's?",
				"options": [
					{"id": "pharmacy", "label": "Raid the pharmacy", "desc": "+1 Serum sample for whoever has least, but Outbreak +1",
						"effects": [{"op": "serum", "samples": 1, "to": "least_serum"}, {"op": "outbreak", "amount": 1}],
						"outcome": "The nurse watches you take it. She doesn't try to stop you. She just writes down how much."},
					{"id": "rest", "label": "Rest in the staff room", "desc": "Every soldier heals 25%; 30% chance the patients wake",
						"effects": [{"op": "heal_pct", "pct": 25, "who": "all"}, {"op": "chance", "p": 0.3,
							"then": [{"op": "fight", "objective": "skirmish", "ambush": true, "small": true}],
							"else": []}],
						"outcome": "Clean beds and running water. Down the corridor, a restraint creaks."},
					{"id": "help", "label": "Help the nurse", "desc": "-20 Supplies, Outbreak -2", "requires": {"supplies": 20},
						"effects": [{"op": "supplies", "amount": -20}, {"op": "outbreak", "amount": -2}],
						"outcome": "You leave her every dose of sedative you have. She says she'll keep them sleeping as long as she can."},
				],
			},
		},
	},
	# ---------------------------------------------------------------- The Bore (act 3)
	"cage_lift": {
		"title": "The cage lift",
		"acts": [3],
		"weight": {3: 2},
		"text": "Shaft 2's personnel cage, rated for twelve, hanging over nine kilometres of dark. The motor is dead. The hand crank still turns, if someone puts their back into it for a very long time.",
		"start": "crank",
		"steps": {
			"crank": {
				"kind": "volunteer",
				"prompt": "Somebody has to crank the cage down.",
				"skip_if_class": {"class": "breacher", "to": "ride",
					"outcome": "Your Breacher hot-wires the motor off a lamp battery. The cage drops with a lurch, then holds."},
				"options": [
					{"id": "crank", "label": "I'll crank", "desc": "One of your soldiers loses 30% HP", "target": "own_soldier",
						"effects": [{"op": "hurt_pct", "pct": 30, "who": "soldier"}],
						"outcome": "{soldier} cranks until their hands bleed through the gloves.", "next": "ride"},
				],
				"nobody": {"outcome": "You take the ladders instead. Two thousand rungs. Outbreak +2.",
					"effects": [{"op": "outbreak", "amount": 2}]},
			},
			"ride": {
				"kind": "vote",
				"prompt": "The cage passes a lit gallery halfway down. Stop?",
				"options": [
					{"id": "stop", "label": "Stop and search", "desc": "+25 Supplies, Outbreak +1",
						"effects": [{"op": "supplies", "amount": 25}, {"op": "outbreak", "amount": 1}],
						"outcome": "A survey crew's stores, untouched. Their tents are untouched too. Their owners are nowhere."},
					{"id": "go", "label": "Keep going", "desc": "Nothing", "default": true,
						"outcome": "The gallery lights slide past and up. Someone in there waves. Nobody waves back."},
				],
			},
		},
	},
	"miners_refuge": {
		"title": "Miners' refuge",
		"acts": [3],
		"text": "A steel refuge chamber bolted into the rock, air scrubbers still running. Inside: six miners on twelve days of rations, and a foreman who hasn't slept since the Bloom came up the shaft. \"Get us out, or give us a reason to keep waiting.\"",
		"start": "choice",
		"steps": {
			"choice": {
				"kind": "vote",
				"prompt": "What do you do for the miners?",
				"options": [
					{"id": "recruit", "label": "Arm the foreman", "desc": "A recruit for the player with the smallest reserve, at 30 Infection",
						"effects": [{"op": "recruit", "count": 1, "infection": 30, "to": "fewest"}],
						"outcome": "The foreman takes a rifle and a headlamp. \"I know these tunnels. I know what's in them now, too.\""},
					{"id": "share", "label": "Share your rations", "desc": "-20 Supplies, every soldier heals 20%", "requires": {"supplies": 20},
						"effects": [{"op": "supplies", "amount": -20}, {"op": "heal_pct", "pct": 20, "who": "all"}],
						"outcome": "Everyone eats together in the refuge. For half an hour, nobody is a soldier."},
					{"id": "take", "label": "Take their stores", "desc": "+30 Supplies, Outbreak +1",
						"effects": [{"op": "supplies", "amount": 30}, {"op": "outbreak", "amount": 1}],
						"outcome": "The foreman doesn't fight you for it. He just closes the hatch behind you, very slowly."},
				],
			},
		},
	},
	"root_vein": {
		"title": "Root vein",
		"acts": [3],
		"weight": {3: 2},
		"text": "A root as thick as a tram car runs down the gallery wall, pulsing in time with something far below. Touch the rock near it and you can feel the Source thinking. It's warm. It's waiting.",
		"start": "choice",
		"steps": {
			"choice": {
				"kind": "secret",
				"prompt": "Cut the vein, or drink from it? Everyone decides in private.",
				"options": [
					{"id": "cut", "label": "Cut it", "desc": "Your soldier gains 10 Infection from the spray. If everyone cuts, Outbreak -3", "target": "own_soldier", "default": true,
						"effects": [{"op": "infection", "amount": 10, "who": "soldier"}],
						"outcome": "{soldier} hacks into the root. It bleeds light."},
					{"id": "drink", "label": "Drink from it", "desc": "Your soldier gets a perk pick and +20 Infection", "target": "own_soldier",
						"effects": [{"op": "perk_pick", "who": "soldier"}, {"op": "infection", "amount": 20, "who": "soldier"}],
						"outcome": "{soldier} puts their lips to the bark. For a moment they understand everything. Then most of it fades."},
				],
				"unanimous": {"option": "cut", "effects": [{"op": "outbreak", "amount": -3}],
					"outcome": "The root parts with a sound like a breaking bone. Far below, the pulse stutters."},
			},
		},
	},
	"drill_crew": {
		"title": "Drill crew",
		"acts": [3],
		"text": "Drill Rig 7, still running on its own power. The crew is still at their stations, Turned where they stood, overgrown into the machinery. The rig's armoury locker is right behind them.",
		"start": "choice",
		"steps": {
			"choice": {
				"kind": "vote",
				"prompt": "The crew hasn't moved yet. What do you do?",
				"options": [
					{"id": "sneak", "label": "Sneak to the locker", "desc": "Everyone picks 1 of 2 Rare items, unless the crew wakes (50%) and you fight instead", "next": "loot",
						"effects": [{"op": "chance", "p": 0.5,
							"then": [{"op": "fight", "objective": "purge", "ambush": true}],
							"else": []}],
						"outcome": "Step by step past the crew. One of them turns its head to follow you. Just its head."},
					{"id": "burn", "label": "Burn them where they stand", "desc": "Free with a Hazmat, otherwise -25 Supplies of fuel; Outbreak -1",
						"requires": {"supplies": 25, "waived_by": "hazmat"},
						"effects": [{"op": "supplies", "amount": -25, "unless_class": "hazmat"}, {"op": "outbreak", "amount": -1}],
						"outcome": "They don't scream. The rig does, metal warping in the heat."},
					{"id": "leave", "label": "Leave them be", "desc": "Nothing", "default": true,
						"outcome": "Some things you let lie. You back out the way you came."},
				],
			},
			"loot": {
				"kind": "per_player",
				"prompt": "Every player takes one of two items for one of their soldiers.",
				"generate": {"items": 2, "rarity": "rare"},
				"options": [],
			},
		},
	},
	"seismic_charges": {
		"title": "Seismic charges",
		"acts": [3],
		"text": "A Cordon demolition team, what's left of it, wiring the gallery to collapse. \"Command's orders: seal the Bore, whoever's still down here.\" Their sergeant looks at your squad, at the glow, and doesn't finish the thought.",
		"start": "choice",
		"steps": {
			"choice": {
				"kind": "vote",
				"prompt": "What do you do about the charges?",
				"options": [
					{"id": "help", "label": "Cover them while they wire it", "desc": "Fight now (Hold): Outbreak -3",
						"effects": [{"op": "outbreak", "amount": -3}, {"op": "fight", "objective": "hold"}],
						"outcome": "\"Ten minutes, Lantern. Give us ten minutes.\" The tunnel behind you starts to fill with sound."},
					{"id": "take", "label": "Take some charges", "desc": "Every player picks 1 of 2 Uncommon items; Outbreak +1",
						"effects": [{"op": "outbreak", "amount": 1}], "next": "kit",
						"outcome": "The sergeant hands them over without argument. He doesn't plan to need them for long."},
					{"id": "leave", "label": "Leave them to it", "desc": "Nothing", "default": true,
						"outcome": "You leave them to their wiring. Ten minutes later, the whole mountain shrugs."},
				],
			},
			"kit": {
				"kind": "per_player",
				"prompt": "Every player takes one of two items for one of their soldiers.",
				"generate": {"items": 2, "rarity": "uncommon"},
				"options": [],
			},
		},
	},
}


## Text shown when no event is left to draw (every event already seen this run).
const QUIET_STREETS := {
	"title": "Quiet streets",
	"text": "Nothing here but wind through broken windows and a Cordon cache nobody got to.",
	"supplies": 20,
}
