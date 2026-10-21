class_name TcpBus
extends RefCounted

## Real TCP transport over 127.0.0.1 with the same endpoint API as
## LoopbackBus: send(to_id, msg), poll() -> [{from, msg}]. Star topology:
## one host endpoint listens; client endpoints connect to it. Framing is
## newline-delimited JSON envelopes {from, to, msg}. The host learns a
## client's endpoint id from its first envelope (clients say hello first).

var my_id: String
var port: int = 0
var listen_error: int = OK

var _server: TCPServer = null
var _peer: StreamPeerTCP = null # client mode: the single host connection
var _peers: Dictionary = {} # host mode: remote_id -> StreamPeerTCP
var _unidentified: Array = [] # host mode: accepted peers, no envelope yet
var _buffers: Dictionary = {} # peer instance_id -> partial line (String)
var _inbox: Array = []
var _outbox: Array = [] # client mode: lines queued until connected

static func host_endpoint(id: String, p: int) -> TcpBus:
	var b := TcpBus.new()
	b.my_id = id
	b.port = p
	b._server = TCPServer.new()
	b.listen_error = b._server.listen(p, "127.0.0.1")
	return b

static func client_endpoint(id: String, addr: String, p: int) -> TcpBus:
	var b := TcpBus.new()
	b.my_id = id
	b.port = p
	b._peer = StreamPeerTCP.new()
	b._peer.connect_to_host(addr, p)
	return b

func is_connected_to(id: String) -> bool:
	if _peer != null:
		return id == "host" and _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED
	var p: StreamPeerTCP = _peers.get(id, null)
	return p != null and p.get_status() == StreamPeerTCP.STATUS_CONNECTED

func send(to_id: String, msg: Dictionary) -> void:
	var line := JSON.stringify({"from": my_id, "to": to_id, "msg": msg}) + "\n"
	if _peer != null:
		if _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			_peer.put_data(line.to_utf8_buffer())
		else:
			_outbox.append(line)
		return
	var p: StreamPeerTCP = _peers.get(to_id, null)
	if p != null and p.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		p.put_data(line.to_utf8_buffer())

func poll() -> Array:
	if _server != null:
		while _server.is_connection_available():
			var p := _server.take_connection()
			_unidentified.append(p)
			_buffers[p.get_instance_id()] = ""
	if _peer != null:
		_peer.poll()
		if _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			for line in _outbox:
				_peer.put_data(line.to_utf8_buffer())
			_outbox.clear()
			_pump_peer(_peer)
	else:
		var all: Array = _unidentified.duplicate()
		for id in _peers:
			all.append(_peers[id])
		for p in all:
			p.poll()
			if p.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				_pump_peer(p)
	var out := _inbox
	_inbox = []
	return out

func _pump_peer(p: StreamPeerTCP) -> void:
	var avail := p.get_available_bytes()
	if avail <= 0:
		return
	var res: Array = p.get_data(avail)
	if res[0] != OK:
		return
	var key := p.get_instance_id()
	var text: String = String(_buffers.get(key, "")) + (res[1] as PackedByteArray).get_string_from_utf8()
	var lines := text.split("\n")
	_buffers[key] = lines[lines.size() - 1]
	for i in range(lines.size() - 1):
		if lines[i].strip_edges() == "":
			continue
		var parsed = JSON.parse_string(lines[i])
		if parsed == null:
			continue
		var from_id := String(parsed.get("from", ""))
		if _server != null and from_id != "" and not _peers.has(from_id):
			_peers[from_id] = p
			_unidentified.erase(p)
		_inbox.append({"from": from_id, "msg": parsed.get("msg", {})})

func close() -> void:
	if _peer != null and _peer.get_status() != StreamPeerTCP.STATUS_NONE:
		_peer.disconnect_from_host()
	for id in _peers:
		(_peers[id] as StreamPeerTCP).disconnect_from_host()
	for p in _unidentified:
		(p as StreamPeerTCP).disconnect_from_host()
	if _server != null:
		_server.stop()
