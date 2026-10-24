class_name EnetTransport
extends NetTransport
## Direct connections by IP address: LAN, a forwarded port, Tailscale, and the CI playtests.

## How long the host waits on a silent peer before dropping it (ms). ENet's default is ~30s, which
## left crashed clients in the lobby long enough to push a rejoining player into the wrong slot.
const PEER_TIMEOUT_MS := 5000

var address := ""
var port := 0
var max_clients := 3


func _init(p_address: String = "", p_port: int = 0, p_max_clients: int = 3) -> void:
	address = p_address
	port = p_port
	max_clients = p_max_clients


func kind() -> String:
	return "enet"


func host() -> String:
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_server(port, max_clients)
	if err != OK:
		return "Could not open port %d (%s)" % [port, error_string(err)]
	peer = enet
	return ""


func join() -> String:
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_client(address, port)
	if err != OK:
		return "Could not connect to %s:%d (%s)" % [address, port, error_string(err)]
	peer = enet
	return ""


func rejoin_copy() -> NetTransport:
	return EnetTransport.new(address, port, max_clients)


func describe() -> String:
	return "%s:%d" % [address, port]


func on_peer_connected(id: int) -> void:
	var enet := peer as ENetMultiplayerPeer
	if enet != null and enet.get_peer(id) != null:
		enet.get_peer(id).set_timeout(PEER_TIMEOUT_MS / 2, PEER_TIMEOUT_MS / 2, PEER_TIMEOUT_MS)
