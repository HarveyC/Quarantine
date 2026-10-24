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
##             target_requires: {"has_mutation": true, "infection_at_least": n, "infection_below": n}
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
##   serum {samples, to: "player"|"least_serum"}
##   recruit {count, infection, to: "player"|"fewest", carrier}   (carrier: one of them is a hidden carrier)
##   item {count, rarity, who}   (drawn and equipped on that soldier)
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
}


## Text shown when no event is left to draw (every event already seen this run).
const QUIET_STREETS := {
	"title": "Quiet streets",
	"text": "Nothing here but wind through broken windows and a Cordon cache nobody got to.",
	"supplies": 20,
}
