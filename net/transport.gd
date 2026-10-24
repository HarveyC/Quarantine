class_name NetTransport
extends RefCounted
## How a NetSession reaches the other players. NetSession only sees the MultiplayerPeer this
## makes, so the replication code is the same over ENet (LAN, port forward, dev) and Steam.
##
## ENet makes its peer inside host()/join(). Steam has to create or enter a lobby first, so its
## `peer` stays null until `ready` fires with it; `failed` fires with a reason if it never will.

signal ready(peer: MultiplayerPeer)
signal failed(reason: String)

var peer: MultiplayerPeer


## Short name for logs and the HUD: "enet" or "steam".
func kind() -> String:
	return ""


## Starts hosting. Returns "" if under way (watch `ready`), otherwise a reason.
func host() -> String:
	return "Not supported"


## Starts joining. Returns "" if under way (watch `ready`), otherwise a reason.
func join() -> String:
	return "Not supported"


## A fresh transport aimed at the same host, for reconnecting after a dropped connection.
func rejoin_copy() -> NetTransport:
	return null


## What a client shows while connecting, e.g. "192.168.1.20:24680" or "a Steam lobby".
func describe() -> String:
	return ""


## Host: called when a peer connects (ENet uses it to shorten the silent-peer timeout).
func on_peer_connected(_id: int) -> void:
	pass


## Host: cuts one peer off now.
func disconnect_peer(id: int) -> void:
	if peer != null:
		peer.disconnect_peer(id)


## A stable id for this player on this transport, or "" to use the per-install id.
func player_id() -> String:
	return ""


func close() -> void:
	if peer != null:
		peer.close()
	peer = null
