class_name NetSession
extends Node
## Online co-op, host-authoritative, over a NetTransport: ENet by address (LAN, port forward,
## dev and CI) or Steam lobbies with relayed traffic (no port forwarding).
##
## Every peer runs the same deterministic rules on the same seed. Clients never change
## their state on their own: they send action requests to the host, the host validates
## them (including that the sender owns the soldier), applies them, and broadcasts the
## accepted action with a sequence number and a checksum of the resulting state. Clients
## apply it and compare checksums; on a mismatch or a gap they ask for a full snapshot.
##
## This node must sit at the same path on every peer (App adds it as "Net").
##
## A client that loses the host mid-match (Wi-Fi drop, relay hiccup) keeps its state and tries to
## reconnect a few times; the host keeps its slot as absent and hands it back on the same client id.
## A host that quits on purpose says goodbye first, so clients don't wait on a reconnect.

signal lobby_changed
signal match_started(state: GameState)
signal resynced(state: GameState)
signal rejected(reason: String)
signal disconnected(reason: String)
signal run_changed(run: RunState)
## Client: the connection to the host dropped mid-match and we're trying again.
signal reconnecting(attempt: int, of: int)
## Client: back in the match after a drop.
signal reconnected

const DEFAULT_PORT := 24680
const MAX_PLAYERS := 4
const READY := "ready"   # pseudo action type: {"type": READY, "player": int, "ready": bool}
const RUN := "run"       # wrapper for run actions: {"type": RUN, "action": <RunRules action>}
## Seconds after the first route vote before the host closes the vote (design doc: 20).
const VOTE_SECONDS := 20.0
## How long the host waits on a silent ENet peer before dropping it (ms).
const PEER_TIMEOUT_MS := EnetTransport.PEER_TIMEOUT_MS
## Seconds to wait before each reconnect attempt; the client gives up after the last.
const RECONNECT_DELAYS: Array[float] = [1.0, 2.0, 3.0, 4.0, 5.0, 5.0]
const CLIENT_ID_PATH := "user://client_id.txt"

var state: GameState
## The roguelike run, when the match is a run (start_run) rather than a single mission.
var run: RunState
## Host: a saved run to continue instead of starting a new one (set from the menu).
var resume: RunState
var my_name := "Player"
var is_host := false
var my_player := -1
var in_match := false
## peer id -> {"name": String, "player": int}. Owned by the host, mirrored to clients.
var lobby := {}
## Stable per-install id sent on join, so the host can tell a reconnect from a new player.
var client_id := ""
## Host only: players whose peer dropped mid-match. Their soldiers hunker and they auto-ready.
var absent := {}
var player_names := {}

var _seq := 0
var _config := {}
var _waiting := false
var _absent_pending := false
var transport: NetTransport
## Client: reconnect attempt in progress (1-based), 0 when connected normally.
var _reconnect_attempt := 0
var _host_said_bye := false
## Dev/test aid (--drop-client-at=N): the host cuts the first client off after action N.
var drop_client_at := -1


# --- connecting --------------------------------------------------------------

## Hosts over ENet on `port`. Returns "" on success, otherwise a reason.
func host(port: int, name: String) -> String:
	return host_with(EnetTransport.new("", port, MAX_PLAYERS - 1), name)


## Joins a host over ENet by address. Returns "" if connecting, otherwise a reason.
func join(address: String, port: int, name: String) -> String:
	return join_with(EnetTransport.new(address, port), name)


## Hosts a friends-only Steam lobby. Returns "" if under way, otherwise a reason.
func host_steam(steam, name: String) -> String:
	var t := SteamTransport.new(steam)
	t.max_members = MAX_PLAYERS
	return host_with(t, name)


## Joins the host of a Steam lobby (from an invite, the friends list or +connect_lobby).
func join_steam(steam, lobby: int, name: String) -> String:
	return join_with(SteamTransport.new(steam, lobby), name)


func via_steam() -> bool:
	return transport is SteamTransport


## The Steam lobby we're in, or 0.
func steam_lobby() -> int:
	return (transport as SteamTransport).lobby_id if transport is SteamTransport else 0


## Host over Steam: opens the overlay's invite dialog. False if that isn't possible.
func invite_friends() -> bool:
	return transport is SteamTransport and (transport as SteamTransport).invite_friends()


func is_reconnecting() -> bool:
	return _reconnect_attempt > 0


func host_with(t: NetTransport, name: String) -> String:
	var err := _attach(t, name, t.host)
	if err != "":
		return err
	is_host = true
	my_player = 0
	lobby = {1: {"name": my_name, "player": 0}}
	lobby[1]["cid"] = client_id
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_refresh_names()
	lobby_changed.emit()
	return ""


func join_with(t: NetTransport, name: String) -> String:
	var err := _attach(t, name, t.join)
	if err != "":
		return err
	_watch_host()
	return ""


func _watch_host() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_host)
	multiplayer.connection_failed.connect(_on_host_lost.bind(true))
	multiplayer.server_disconnected.connect(_on_host_lost.bind(false))


func _on_connected_to_host() -> void:
	_hello.rpc_id(1, my_name, client_id)


func leave() -> void:
	if is_host and _live() and in_match:
		# Tell clients this is on purpose so they don't sit through reconnect attempts.
		_bye.rpc()
		multiplayer.multiplayer_peer.poll()
	_close_transport()
	in_match = false
	is_host = false
	my_player = -1
	run = null
	lobby = {}
	absent = {}
	player_names = {}
	_waiting = false
	_reconnect_attempt = 0
	_host_said_bye = false


## Closes the connection and forgets the transport, keeping the match state (for reconnects).
func _close_transport() -> void:
	if transport != null:
		if transport.ready.is_connected(_on_transport_ready):
			transport.ready.disconnect(_on_transport_ready)
		if transport.failed.is_connected(_on_transport_failed):
			transport.failed.disconnect(_on_transport_failed)
		transport.close()
		transport = null
	if is_inside_tree():
		multiplayer.multiplayer_peer = null
		for sig in [multiplayer.peer_connected, multiplayer.peer_disconnected, multiplayer.connected_to_server,
				multiplayer.connection_failed, multiplayer.server_disconnected]:
			for c in sig.get_connections():
				sig.disconnect(c.callable)


## Starts `t` with `start` (its host or join). Returns "" if under way, otherwise a reason.
func _attach(t: NetTransport, name: String, start: Callable) -> String:
	# A second Host/Join while already connected would leave a stray connection on the host.
	if transport != null or (is_inside_tree() and multiplayer.multiplayer_peer != null):
		leave()
	my_name = name.strip_edges() if name.strip_edges() != "" else "Player"
	if client_id == "":
		client_id = load_client_id(my_name if Array(OS.get_cmdline_user_args()).any(func(a: String) -> bool: return a.begins_with("--name=")) else "")
	if t.player_id() != "":
		client_id = t.player_id()   # a Steam id follows the player across installs
	var err: String = start.call()
	if err != "":
		return err
	transport = t
	if t.peer != null:
		multiplayer.multiplayer_peer = t.peer
	else:
		t.ready.connect(_on_transport_ready)
		t.failed.connect(_on_transport_failed)
	return ""


func _on_transport_ready(peer: MultiplayerPeer) -> void:
	multiplayer.multiplayer_peer = peer
	lobby_changed.emit()   # e.g. the Steam lobby now exists, so invites work


func _on_transport_failed(reason: String) -> void:
	if _reconnect_attempt > 0:
		_on_host_lost(true)
	else:
		_drop(reason)


## A random id saved once per install. `suffix` keeps several dev copies on one machine distinct.
static func load_client_id(suffix: String = "") -> String:
	var id := FileAccess.get_file_as_string(CLIENT_ID_PATH).strip_edges()
	if id == "":
		id = "%x%x" % [randi(), randi()]
		var f := FileAccess.open(CLIENT_ID_PATH, FileAccess.WRITE)
		if f:
			f.store_string(id)
	return id + ("/" + suffix if suffix != "" else "")


func _drop(reason: String) -> void:
	leave()
	disconnected.emit(reason)


# --- reconnecting (client) ------------------------------------------------------

@rpc("authority", "reliable")
func _bye() -> void:
	_host_said_bye = true


## Whether a dropped connection is worth getting back: a match is still going.
func _match_live() -> bool:
	if not in_match or is_host:
		return false
	if run != null:
		return run.phase != RunState.Phase.ENDED
	return state != null and state.phase != Types.Phase.ENDED


## The host went away (`failed`: a connect attempt failed). Mid-match, retry; otherwise give up.
func _on_host_lost(failed: bool) -> void:
	if _host_said_bye or not _match_live() or transport == null:
		if failed and _reconnect_attempt == 0 and not in_match:
			_drop("Could not reach the host at %s" % transport.describe() if transport else "Could not reach the host")
		else:
			_drop("The host left the game")
		return
	if _reconnect_attempt >= RECONNECT_DELAYS.size():
		_drop("Lost the connection to the host")
		return
	var again := transport.rejoin_copy()
	_close_transport()
	_waiting = false
	_reconnect_attempt += 1
	print("[net] connection lost; reconnecting (%d/%d)" % [_reconnect_attempt, RECONNECT_DELAYS.size()])
	reconnecting.emit(_reconnect_attempt, RECONNECT_DELAYS.size())
	var attempt := _reconnect_attempt
	get_tree().create_timer(RECONNECT_DELAYS[attempt - 1]).timeout.connect(func() -> void:
		if _reconnect_attempt != attempt or again == null:
			return
		var err := _attach_again(again)
		if err != "":
			_on_host_lost(true))


func _attach_again(t: NetTransport) -> String:
	var err: String = t.join()
	if err != "":
		transport = t
		return err
	transport = t
	_watch_host()
	if t.peer != null:
		multiplayer.multiplayer_peer = t.peer
	else:
		t.ready.connect(_on_transport_ready)
		t.failed.connect(_on_transport_failed)
	return ""


## Local IPv4 addresses, to tell a friend where to connect.
static func local_addresses() -> Array[String]:
	var out: Array[String] = []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out


# --- session interface used by the view (same as LocalSession) -----------------

func local_players() -> Array[int]:
	return [my_player] as Array[int]


func is_local(player: int) -> bool:
	return player == my_player


func can_restart() -> bool:
	return is_host and run == null


func is_waiting() -> bool:
	return _waiting


func submit(action: Dictionary) -> void:
	if is_reconnecting():
		rejected.emit("Reconnecting to the host...")
		return
	var err := Rules.validate(state, action)
	if err != "":
		rejected.emit(err)
		return
	_send(action)


func set_ready(player: int, on: bool) -> void:
	if is_reconnecting():
		rejected.emit("Reconnecting to the host...")
		return
	_send({"type": READY, "player": player, "ready": on})


func submit_run(action: Dictionary) -> void:
	if run == null:
		return
	if is_reconnecting():
		rejected.emit("Reconnecting to the host...")
		return
	var err := RunRules.validate(run, action)
	if err != "":
		rejected.emit(err)
		return
	_send({"type": RUN, "action": action})


func restart() -> void:
	if is_host:
		start_match()


func status_text() -> String:
	var others := lobby.size() - 1
	if is_reconnecting():
		return "Reconnecting to the host (%d/%d)..." % [_reconnect_attempt, RECONNECT_DELAYS.size()]
	var how := " on Steam" if via_steam() else ""
	return "%s%s · %d player%s" % ["Hosting" if is_host else "Online", how, lobby.size(), "" if others == 0 else "s"]


func _send(action: Dictionary) -> void:
	_waiting = true
	if is_host:
		_handle_request(1, action)
	else:
		_request.rpc_id(1, action)


# --- lobby --------------------------------------------------------------------

## The class each lobby player picked for their soldier (co-op is one soldier per player).
func class_picks() -> Dictionary:
	var out := {}
	for v in lobby.values():
		if v.get("class", "") != "":
			out[v.player] = v["class"]
	return out


## Picks the class of this player's soldier for the next match or run.
func pick_class(kind: String) -> void:
	if is_host:
		handle_pick(1, kind)
	elif _live():
		_pick_class.rpc_id(1, kind)


@rpc("any_peer", "reliable")
func _pick_class(kind: String) -> void:
	if is_host:
		handle_pick(multiplayer.get_remote_sender_id(), kind)


## Host: a lobby peer picked a class. Ignored mid-match and for classes the host hasn't unlocked.
func handle_pick(id: int, kind: String) -> void:
	if in_match or not lobby.has(id) or not Progression.unlocked_classes(Profile.meta()).has(kind):
		return
	lobby[id]["class"] = kind
	_broadcast_lobby()


## Host: begin (or restart) the mission with everyone currently connected.
func start_match() -> void:
	if not is_host:
		return
	absent.clear()
	# Re-number players 0..n-1 in join order so the squad split has no gaps.
	var ids := lobby.keys()
	ids.sort()
	for i in ids.size():
		lobby[ids[i]].player = i
	_broadcast_lobby()
	var config := MatchConfig.make(lobby.size(), 0, class_picks())
	if _live():
		_start.rpc(config)
	_start(config)


## Host: begin a roguelike run with everyone connected, or continue `resume`. The host builds the
## run from a seed and sends the whole RunState once; after that only run actions travel.
func start_run() -> void:
	if not is_host:
		return
	absent.clear()
	var ids := lobby.keys()
	ids.sort()
	for i in ids.size():
		lobby[ids[i]].player = i
	_broadcast_lobby()
	if resume != null:
		run = resume
		resume = null
		# Players from the save who aren't here are benched until they join.
		var here := {}
		for v in lobby.values():
			here[v.player] = true
		for p in run.players:
			if p != run.host_player and not here.has(p):
				RunRules.apply(run, {"type": RunRules.BENCH, "player": run.host_player, "target": p, "on": true})
	else:
		run = RunRules.new_run(lobby.size(), 0, Profile.meta(), class_picks())
		RunRules.start_run(run)
	var snap := run.fight_snapshot if run.phase == RunState.Phase.FIGHT else {}
	if _live():
		_run_start.rpc(run.to_dict(), snap)
	_run_start(run.to_dict(), snap)
	if is_inside_tree():
		_watch_run()


@rpc("authority", "reliable")
func _run_start(run_dict: Dictionary, snapshot: Dictionary) -> void:
	_seq = 0
	_waiting = false
	in_match = true
	_config = {}
	run = RunState.from_dict(run_dict)
	state = null
	print("[net] run started: I am player %d of %d" % [my_player + 1, run.players.size()])
	_install_run(snapshot)


## Builds the fight on this peer if the run is in one (every peer builds the same GameState from
## run.fight_config), then tells the view.
func _install_run(snapshot: Dictionary = {}) -> void:
	if run.phase == RunState.Phase.FIGHT:
		if not snapshot.is_empty():
			state = GameState.from_dict(snapshot)
			state.event.connect(_on_mission_event)
			resynced.emit(state)
		elif state == null or state.phase == Types.Phase.ENDED:
			state = MatchConfig.build(run.fight_config)
			state.event.connect(_on_mission_event)
			match_started.emit(state)
	if is_host:
		RunSave.write(run)
		Profile.record_run(run)
	run_changed.emit(run)


func _on_mission_event(ev: Dictionary) -> void:
	if not is_host or run == null:
		return
	match ev.type:
		"team_phase":
			run.fight_snapshot = state.to_dict()
			RunSave.write(run)
		"mission_end":
			# Deferred: we're inside the mission action's _apply, which commits after this returns.
			_report_fight.call_deferred(RunRules.fight_outcome(state))


func _report_fight(outcome: Dictionary) -> void:
	if run != null and run.phase == RunState.Phase.FIGHT:
		_commit_host({"type": RUN, "action": {"type": RunRules.FIGHT_END, "player": run.host_player, "outcome": outcome}})


## Host: closes a route vote VOTE_SECONDS after its first pin, counting the votes cast.
func _watch_run() -> void:
	if not run.event.is_connected(_on_run_event):
		run.event.connect(_on_run_event)


func _on_run_event(ev: Dictionary) -> void:
	if ev.type != "vote" or not is_host or not is_inside_tree() or run.votes.size() != 1:
		return
	var at := run.node
	var act := run.act
	get_tree().create_timer(VOTE_SECONDS).timeout.connect(func() -> void:
		if run != null and run.phase == RunState.Phase.MAP and run.node == at and run.act == act and not run.votes.is_empty():
			_commit_host({"type": RUN, "action": {"type": RunRules.CLOSE_VOTE, "player": run.host_player}}))


@rpc("any_peer", "reliable")
func _hello(name: String, cid: String = "") -> void:
	if is_host:
		handle_hello(multiplayer.get_remote_sender_id(), name, cid)


## Host: a peer introduced itself. Returns the player slot it got, or -1 if it was turned away.
func handle_hello(id: int, name: String, cid: String) -> int:
	if lobby.has(id):
		return lobby[id].player   # duplicate hello from the same connection
	var slot := -1
	# Same install reconnecting (crash, restart, Wi-Fi drop): take over its old slot and drop
	# the dead connection now instead of waiting for it to time out.
	for old_id in lobby.keys():
		if cid != "" and old_id != id and lobby[old_id].get("cid", "") == cid:
			slot = lobby[old_id].player
			lobby.erase(old_id)
			_drop_peer(old_id)
			break
	if slot < 0:
		slot = _free_slot(name)
	if slot < 0:
		_send_kick(id, "That game is full" if not in_match else "That match is full or already running")
		return -1
	lobby[id] = {"name": name, "player": slot, "cid": cid}
	absent.erase(slot)
	_broadcast_lobby()
	if in_match and run != null and run.benched.get(slot, false):
		_commit_host({"type": RUN, "action": {"type": RunRules.BENCH, "player": run.host_player, "target": slot, "on": false}})
	if in_match:
		_send_sync(id)
	return slot


func _on_peer_connected(id: int) -> void:
	if transport != null:
		transport.on_peer_connected(id)


# Network sends, skipped when the session isn't live (unit tests drive the host logic directly).
func _live() -> bool:
	return is_inside_tree() and multiplayer.multiplayer_peer != null


func _broadcast_lobby() -> void:
	if _live():
		_lobby.rpc(lobby)
	_set_lobby(lobby)


func _send_sync(id: int) -> void:
	if _live():
		_sync.rpc_id(id, _config, state.to_dict() if state else {}, _seq, run.to_dict() if run else {})


func _send_kick(id: int, reason: String) -> void:
	if _live():
		_kick.rpc_id(id, reason)


func _drop_peer(id: int) -> void:
	if _live() and transport != null:
		transport.disconnect_peer(id)


## Lobby: next unused player number. Mid-match: an absent player's slot, preferring the same name.
func _free_slot(name: String) -> int:
	var used := {}
	for v in lobby.values():
		used[v.player] = true
	if not in_match:
		for p in MAX_PLAYERS:
			if not used.has(p):
				return p
		return -1
	for p in absent:
		if player_names.get(p, "") == name:
			return p
	return absent.keys()[0] if not absent.is_empty() else -1


func _on_peer_disconnected(id: int) -> void:
	if not lobby.has(id):
		return
	var p: int = lobby[id].player
	lobby.erase(id)
	if in_match:
		absent[p] = true
	_broadcast_lobby()
	if in_match and run != null and p != run.host_player and run.players.has(p):
		_commit_host({"type": RUN, "action": {"type": RunRules.BENCH, "player": run.host_player, "target": p, "on": true}})
	_queue_absent_turns()


@rpc("authority", "reliable")
func _lobby(l: Dictionary) -> void:
	_set_lobby(l)


func _set_lobby(l: Dictionary) -> void:
	lobby = l
	var me := multiplayer.get_unique_id() if _live() else 1
	if lobby.has(me):
		my_player = lobby[me].player
	_refresh_names()
	lobby_changed.emit()


func _refresh_names() -> void:
	# Keep names of players who dropped so the HUD can still label their soldiers.
	for v in lobby.values():
		player_names[v.player] = v.name


@rpc("authority", "reliable")
func _kick(reason: String) -> void:
	_drop(reason)


# --- match flow ---------------------------------------------------------------

@rpc("authority", "reliable")
func _start(config: Dictionary) -> void:
	_config = config
	_seq = 0
	_waiting = false
	in_match = true
	run = null
	state = MatchConfig.build(config)
	print("[net] match started: I am player %d of %d" % [my_player + 1, state.players.size()])
	match_started.emit(state)   # the view connects to events, then calls Rules.start_mission


@rpc("any_peer", "reliable")
func _request(action: Dictionary) -> void:
	if is_host:
		_handle_request(multiplayer.get_remote_sender_id(), action)


func _handle_request(sender: int, action: Dictionary) -> void:
	var err := _check_request(sender, action)
	if err != "":
		if sender == 1:
			_on_rejected(err)
		else:
			_rejected.rpc_id(sender, err)
		return
	_commit_host(action)
	if sender != 1:
		_ack.rpc_id(sender)
	else:
		_waiting = false


func _check_request(sender: int, action: Dictionary) -> String:
	if not in_match or (state == null and run == null):
		return "No match running"
	if not lobby.has(sender):
		return "Not in this game"
	var player: int = lobby[sender].player
	if action.get("type") == RUN:
		if run == null:
			return "No run going"
		var inner: Dictionary = action.get("action", {})
		if inner.get("player") != player:
			return "You can only act for yourself"
		return RunRules.validate(run, inner)
	if state == null:
		return "No fight running"
	if action.get("type") == READY:
		if action.get("player") != player:
			return "That's not your READY button"
		return "" if state.phase == Types.Phase.TEAM else "Wait for the squad phase"
	var u := state.get_unit(action.get("unit", -1))
	if u == null or u.owner_player != player:
		return "That soldier belongs to another player"
	return Rules.validate(state, action)


func _commit_host(action: Dictionary) -> void:
	_seq += 1
	_apply(action)
	if _live():
		_commit.rpc(_seq, action, _checksum())
	if _seq == drop_client_at:
		_drop_first_client.call_deferred()
	_queue_absent_turns()


func _drop_first_client() -> void:
	for id in lobby:
		if id != 1:
			print("[net] test: cutting off player %d" % (lobby[id].player + 1))
			_drop_peer(id)
			return


@rpc("authority", "reliable")
func _commit(seq: int, action: Dictionary, checksum: int) -> void:
	if (state == null and run == null) or seq != _seq + 1:
		_request_sync.rpc_id(1)
		return
	_seq = seq
	_apply(action)
	if _checksum() != checksum:
		push_warning("[net] state drifted from host at action %d; resyncing" % seq)
		_request_sync.rpc_id(1)


func _apply(action: Dictionary) -> void:
	if action.type == RUN:
		RunRules.apply(run, action.action)
		_install_run()
	elif action.type == READY:
		Rules.set_ready(state, action.player, action.ready)
	else:
		Rules.apply(state, action)


## Run and mission together, so a drift in either triggers a resync.
func _checksum() -> int:
	return hash([run.checksum() if run else 0, state.checksum() if state else 0])


@rpc("authority", "reliable")
func _ack() -> void:
	_waiting = false


@rpc("authority", "reliable")
func _rejected(reason: String) -> void:
	_on_rejected(reason)


func _on_rejected(reason: String) -> void:
	_waiting = false
	rejected.emit(reason)


@rpc("any_peer", "reliable")
func _request_sync() -> void:
	if is_host and in_match:
		_sync.rpc_id(multiplayer.get_remote_sender_id(), _config, state.to_dict() if state else {}, _seq, run.to_dict() if run else {})


@rpc("authority", "reliable")
func _sync(config: Dictionary, snapshot: Dictionary, seq: int, run_dict: Dictionary = {}) -> void:
	_config = config
	_seq = seq
	_waiting = false
	in_match = true
	if _reconnect_attempt > 0:
		_reconnect_attempt = 0
		print("[net] reconnected at action %d" % seq)
		reconnected.emit()
	if not run_dict.is_empty():
		run = RunState.from_dict(run_dict)
		state = null
		_install_run(snapshot if run.phase == RunState.Phase.FIGHT else {})
		return
	state = GameState.from_dict(snapshot)
	resynced.emit(state)


# --- absent players -----------------------------------------------------------

func _queue_absent_turns() -> void:
	if is_host and in_match and not absent.is_empty() and not _absent_pending:
		_absent_pending = true
		_play_absent_turns.call_deferred()


## Disconnected players' soldiers hunker down and their READY is pressed for them.
func _play_absent_turns() -> void:
	_absent_pending = false
	if not in_match or state == null or state.phase != Types.Phase.TEAM:
		return
	for p in absent.keys():
		for u in state.controllable_units(p):
			var hunker := {"type": Types.HUNKER, "unit": u.id}
			if Rules.validate(state, hunker) == "":
				_commit_host(hunker)
		if state.phase == Types.Phase.TEAM and not state.ready.get(p, false):
			_commit_host({"type": READY, "player": p, "ready": true})
