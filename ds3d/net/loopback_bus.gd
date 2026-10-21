class_name LoopbackBus
extends RefCounted

## In-process message bus with the same endpoint API as TcpBus: named
## endpoints, send(to_id, msg), poll() -> [{from, msg}]. Delivery is queued
## and ordered per sender, modelling a localhost transport without sockets.
## Used by the playable build (and anywhere a session runs on one machine
## without needing the wire proof). Endpoints sharing a network name share
## one set of mailboxes.

static var _networks: Dictionary = {}

var my_id: String
var _queues: Dictionary = {} # endpoint_id -> Array[{from, msg}] (shared ref)

static func endpoint(network: String, id: String) -> LoopbackBus:
	if not _networks.has(network):
		_networks[network] = {}
	var b := LoopbackBus.new()
	b.my_id = id
	b._queues = _networks[network]
	if not b._queues.has(id):
		b._queues[id] = []
	return b

func send(to_id: String, msg: Dictionary) -> void:
	if not _queues.has(to_id):
		_queues[to_id] = []
	_queues[to_id].append({"from": my_id, "msg": msg})

func poll() -> Array:
	var q: Array = _queues.get(my_id, [])
	var out := q.duplicate()
	q.clear()
	return out

func is_connected_to(id: String) -> bool:
	return _queues.has(id)

func close() -> void:
	pass
