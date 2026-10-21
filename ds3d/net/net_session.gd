class_name NetSession
extends RefCounted

## A whole Slice 4 session: one NetHostSession plus two NetClients (A and
## B), wired over one transport. pump() advances the entire session by
## exactly one fixed tick — clients generate, the host steps, clients
## apply — no matter how often or how rarely pump() itself is called.
## That is the fixed-timestep contract: render rate and pump pacing are
## presentation concerns; the sim only moves in whole rounds.

const LoopbackBus = preload("res://net/loopback_bus.gd")
const TcpBus = preload("res://net/tcp_bus.gd")
const NetHostSession = preload("res://net/net_host_session.gd")
const NetClient = preload("res://net/net_client.gd")
const AIBuyer = preload("res://sim/ai_buyer.gd")

var transport_name: String = ""
var host_session: NetHostSession
var client_a: NetClient
var client_b: NetClient
var round_idx: int = 0

var _buses: Array = []

static func loopback(ai_difficulty: String = "normal") -> NetSession:
	var s := NetSession.new()
	s.transport_name = "loopback"
	var net := "session-%d" % Time.get_ticks_usec()
	s._wire(LoopbackBus.endpoint(net, "host"), LoopbackBus.endpoint(net, "client_a"), LoopbackBus.endpoint(net, "client_b"), ai_difficulty)
	return s

static func tcp(port: int, ai_difficulty: String = "normal") -> NetSession:
	var s := NetSession.new()
	s.transport_name = "tcp"
	s._wire(TcpBus.host_endpoint("host", port), TcpBus.client_endpoint("client_a", "127.0.0.1", port), TcpBus.client_endpoint("client_b", "127.0.0.1", port), ai_difficulty)
	return s

func _wire(host_bus, a_bus, b_bus, ai_difficulty: String) -> void:
	_buses = [host_bus, a_bus, b_bus]
	host_session = NetHostSession.new(host_bus)
	client_a = NetClient.new(a_bus, "client_a", "A", null)
	client_b = NetClient.new(b_bus, "client_b", "B", AIBuyer.new(ai_difficulty))

## Hello/welcome handshake: returns true once both clients are welcomed
## and (on TCP) both sockets report CONNECTED to the host.
func wait_connected(cap: int = 200000) -> bool:
	client_a.connect_to_host()
	client_b.connect_to_host()
	var spins := 0
	while spins < cap:
		host_session.poll_messages()
		client_a.poll()
		client_b.poll()
		if client_a.welcomed and client_b.welcomed:
			return true
		spins += 1
		if spins % 1000 == 0:
			OS.delay_msec(1)
	return false

## Advance the session by exactly one fixed tick. Returns false on a
## transport failure (a client's round_ready never arrived).
func pump() -> bool:
	client_a.begin_round(round_idx)
	client_b.begin_round(round_idx)
	if not host_session.step_round(round_idx):
		return false
	client_a.poll()
	client_b.poll()
	round_idx += 1
	return true

func set_ai_difficulty(level: String) -> void:
	client_b.set_ai_difficulty(level)

func is_match_over() -> bool:
	return host_session.host.match_over

func get_command_log() -> Array:
	return host_session.get_command_log()

func host_tick() -> int:
	return host_session.host.tick

func close() -> void:
	for b in _buses:
		b.close()
