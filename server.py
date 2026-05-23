#!/usr/bin/env python3
import json
import os
import secrets
import socket
import subprocess
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Lock
from typing import Any, Dict, Optional, Union
from urllib.parse import urlparse

HOST = os.getenv("POWER_SOCCER_HOST", "0.0.0.0")
PORT = int(os.getenv("POWER_SOCCER_PORT", "3000"))
TTL_SEC = float(os.getenv("POWER_SOCCER_TTL_SEC", "12"))
MATCH_START_TIMEOUT_SEC = float(os.getenv("POWER_SOCCER_MATCH_START_TIMEOUT_SEC", "8"))
PORT_RANGE_START = int(os.getenv("POWER_SOCCER_MATCH_PORT_START", "24565"))
PORT_RANGE_END = int(os.getenv("POWER_SOCCER_MATCH_PORT_END", "24650"))
PUBLIC_HOST = os.getenv("POWER_SOCCER_PUBLIC_HOST", "").strip()
SERVER_EXE = os.getenv("POWER_SOCCER_SERVER_EXE", "").strip()
SERVER_WORKDIR = os.getenv("POWER_SOCCER_SERVER_WORKDIR", "").strip()
DATA_FILE = Path(
	os.getenv(
		"POWER_SOCCER_DATA_FILE",
		str(Path(__file__).resolve().parent / "data" / "active_servers.json"),
	)
)

_LOCK = Lock()
_SERVERS: Dict[str, Dict[str, Any]] = {}
_MATCH_PROCS: Dict[str, subprocess.Popen] = {}


def _now() -> float:
	return time.time()


def _load_registry() -> None:
	global _SERVERS
	if not DATA_FILE.exists():
		return

	try:
		with DATA_FILE.open("r", encoding="utf-8") as handle:
			payload = json.load(handle)
	except (OSError, json.JSONDecodeError):
		return

	if isinstance(payload, dict):
		_SERVERS = {
			str(server_id): entry
			for server_id, entry in payload.items()
			if isinstance(entry, dict)
		}
	else:
		_SERVERS = {}

	_cleanup_locked()


def _save_registry_locked() -> None:
	DATA_FILE.parent.mkdir(parents=True, exist_ok=True)
	temp_path = DATA_FILE.with_suffix(".tmp")
	with temp_path.open("w", encoding="utf-8") as handle:
		json.dump(_SERVERS, handle, indent=2, sort_keys=True)
	temp_path.replace(DATA_FILE)


def _cleanup_locked() -> None:
	expire_before = _now() - TTL_SEC
	expired_ids = [
		server_id
		for server_id, entry in _SERVERS.items()
		if float(entry.get("last_seen_unix", 0.0)) < expire_before
	]
	for server_id in expired_ids:
		_SERVERS.pop(server_id, None)

	_cleanup_dead_processes_locked()


def _cleanup_dead_processes_locked() -> None:
	finished_ids = []
	for match_id, proc in _MATCH_PROCS.items():
		if proc.poll() is not None:
			finished_ids.append(match_id)

	for match_id in finished_ids:
		_MATCH_PROCS.pop(match_id, None)
		_SERVERS.pop(match_id, None)


def _public_server(entry: Dict[str, Any]) -> Dict[str, Any]:
	return {
		"id": entry["id"],
		"name": entry["name"],
		"server_name": entry["name"],
		"ip": entry["ip"],
		"port": entry["port"],
		"players_connected": entry["players_connected"],
		"lobby_size": entry["lobby_size"],
		"is_public": entry["is_public"],
		"has_password": entry["has_password"],
		"state": entry["state"],
		"source": "cloud",
		"ping": -1,
	}


def _extract_remote_ip(handler: BaseHTTPRequestHandler) -> str:
	forwarded = handler.headers.get("X-Forwarded-For", "").split(",")[0].strip()
	if forwarded:
		return forwarded
	return handler.client_address[0]


def _extract_host_header(handler: BaseHTTPRequestHandler) -> str:
	host_header = handler.headers.get("Host", "").strip()
	if host_header == "":
		return ""
	return host_header.split(":", 1)[0]


def _resolve_public_host(handler: Optional[BaseHTTPRequestHandler] = None, fallback: str = "") -> str:
	if PUBLIC_HOST != "":
		return PUBLIC_HOST
	if handler is not None:
		host_header = _extract_host_header(handler)
		if host_header != "":
			return host_header
	return fallback


def _read_json(handler: BaseHTTPRequestHandler) -> Dict[str, Any]:
	content_length = int(handler.headers.get("Content-Length", "0"))
	if content_length <= 0:
		return {}

	raw_body = handler.rfile.read(content_length)
	if not raw_body:
		return {}

	try:
		parsed = json.loads(raw_body.decode("utf-8"))
	except (UnicodeDecodeError, json.JSONDecodeError) as exc:
		raise ValueError("invalid json body") from exc

	if not isinstance(parsed, dict):
		raise ValueError("json body must be an object")

	return parsed


def _sanitize_heartbeat(
	payload: Dict[str, Any],
	handler: BaseHTTPRequestHandler,
	remote_ip: str,
) -> Dict[str, Any]:
	server_id = str(payload.get("id", "")).strip()
	if server_id == "":
		raise ValueError("missing server id")

	port = int(payload.get("port", 0))
	if port <= 0 or port > 65535:
		raise ValueError("invalid port")

	name = str(payload.get("name", payload.get("server_name", "Unnamed Server"))).strip()
	if name == "":
		name = "Unnamed Server"

	players_connected = max(0, int(payload.get("players_connected", 0)))
	lobby_size = max(players_connected, int(payload.get("lobby_size", players_connected)))
	is_dedicated = bool(payload.get("is_dedicated", False))
	explicit_host = str(payload.get("host_ip", "")).strip()
	public_ip = explicit_host if explicit_host != "" else remote_ip
	if is_dedicated:
		public_ip = _resolve_public_host(handler, public_ip)

	return {
		"id": server_id,
		"name": name,
		"ip": public_ip,
		"port": port,
		"players_connected": players_connected,
		"lobby_size": lobby_size,
		"is_public": bool(payload.get("is_public", True)),
		"has_password": bool(payload.get("has_password", False)),
		"state": str(payload.get("state", "res://scenes/Lobby.tscn")),
		"is_dedicated": is_dedicated,
		"last_seen_unix": _now(),
	}


def _pick_free_match_port_locked() -> int:
	used_ports = set()
	for entry in _SERVERS.values():
		used_ports.add(int(entry.get("port", 0)))

	for port in range(PORT_RANGE_START, PORT_RANGE_END + 1):
		if port in used_ports:
			continue
		with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
			try:
				probe.bind(("0.0.0.0", port))
			except OSError:
				continue
		return port

	raise RuntimeError("no free match ports available")


def _spawn_match_process(match_id: str, match_name: str, port: int) -> subprocess.Popen:
	if SERVER_EXE == "":
		raise RuntimeError("POWER_SOCCER_SERVER_EXE is not configured")

	exe_path = Path(SERVER_EXE)
	if not exe_path.exists():
		raise RuntimeError("server executable not found: %s" % exe_path)

	workdir = Path(SERVER_WORKDIR) if SERVER_WORKDIR != "" else exe_path.parent
	cmd = [
		str(exe_path),
		"--server",
		"id",
		match_id,
		"port",
		str(port),
		"server_name",
		match_name,
	]

	return subprocess.Popen(cmd, cwd=str(workdir))


def _wait_for_match_registration(match_id: str) -> Optional[Dict[str, Any]]:
	deadline = _now() + MATCH_START_TIMEOUT_SEC
	while _now() < deadline:
		with _LOCK:
			entry = _SERVERS.get(match_id)
			proc = _MATCH_PROCS.get(match_id)
			if entry is not None and entry.get("state") != "starting":
				return _public_server(entry)
			if proc is not None and proc.poll() is not None:
				break
		time.sleep(0.2)
	return None


def _sanitize_match_request(
	payload: Dict[str, Any],
	handler: BaseHTTPRequestHandler,
) -> Dict[str, Any]:
	match_name = str(payload.get("name", payload.get("server_name", "Cloud Match"))).strip()
	if match_name == "":
		match_name = "Cloud Match"

	match_id = str(payload.get("id", "")).strip()
	if match_id == "":
		match_id = secrets.token_hex(8)

	public_ip = _resolve_public_host(handler, _extract_host_header(handler))
	if public_ip == "":
		raise ValueError("could not determine public host for the match")

	return {
		"id": match_id,
		"name": match_name,
		"is_public": bool(payload.get("is_public", True)),
		"has_password": bool(payload.get("has_password", False)),
		"ip": public_ip,
	}


class LobbyRegistryHandler(BaseHTTPRequestHandler):
	server_version = "PowerSoccerLobbyRegistry/2.0"

	def log_message(self, fmt: str, *args: Any) -> None:
		message = "%s - - [%s] %s" % (
			self.address_string(),
			self.log_date_time_string(),
			fmt % args,
		)
		print(message, flush=True)

	def _write_json(self, status: int, payload: Union[Dict[str, Any], list]) -> None:
		body = json.dumps(payload).encode("utf-8")
		self.send_response(status)
		self.send_header("Content-Type", "application/json")
		self.send_header("Content-Length", str(len(body)))
		self.send_header("Access-Control-Allow-Origin", "*")
		self.send_header("Access-Control-Allow-Headers", "Content-Type")
		self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		self.end_headers()
		self.wfile.write(body)

	def do_OPTIONS(self) -> None:
		self._write_json(HTTPStatus.OK, {"ok": True})

	def do_GET(self) -> None:
		parsed = urlparse(self.path)
		if parsed.path == "/health":
			with _LOCK:
				_cleanup_locked()
				healthy_count = len(_SERVERS)
				running_matches = len(_MATCH_PROCS)
			self._write_json(
				HTTPStatus.OK,
				{
					"ok": True,
					"active_servers": healthy_count,
					"running_matches": running_matches,
					"ttl_sec": TTL_SEC,
				},
			)
			return

		if parsed.path == "/servers":
			with _LOCK:
				_cleanup_locked()
				_save_registry_locked()
				servers = [
					_public_server(entry)
					for entry in sorted(
						_SERVERS.values(),
						key=lambda item: float(item.get("last_seen_unix", 0.0)),
						reverse=True,
					)
					if bool(entry.get("is_public", True))
				]
			self._write_json(HTTPStatus.OK, {"servers": servers})
			return

		self._write_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "not found"})

	def do_POST(self) -> None:
		parsed = urlparse(self.path)

		if parsed.path == "/create-match":
			self._handle_create_match()
			return

		if parsed.path in ("/heartbeat", "/create-lobby"):
			self._handle_heartbeat()
			return

		if parsed.path == "/unregister":
			self._handle_unregister()
			return

		self._write_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "not found"})

	def _handle_create_match(self) -> None:
		try:
			payload = _read_json(self)
			request_info = _sanitize_match_request(payload, self)
		except ValueError as exc:
			self._write_json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
			return

		try:
			with _LOCK:
				_cleanup_locked()
				match_id = request_info["id"]
				while match_id in _MATCH_PROCS or match_id in _SERVERS:
					match_id = secrets.token_hex(8)
				request_info["id"] = match_id
				port = _pick_free_match_port_locked()
				_SERVERS[match_id] = {
					"id": match_id,
					"name": request_info["name"],
					"ip": request_info["ip"],
					"port": port,
					"players_connected": 0,
					"lobby_size": 0,
					"is_public": request_info["is_public"],
					"has_password": request_info["has_password"],
					"state": "starting",
					"is_dedicated": True,
					"last_seen_unix": _now(),
				}
				process = _spawn_match_process(match_id, request_info["name"], port)
				_MATCH_PROCS[match_id] = process
				_save_registry_locked()
		except RuntimeError as exc:
			self._write_json(HTTPStatus.SERVICE_UNAVAILABLE, {"ok": False, "error": str(exc)})
			return
		except OSError as exc:
			self._write_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"ok": False, "error": str(exc)})
			return

		server_info = _wait_for_match_registration(request_info["id"])
		if server_info is None:
			with _LOCK:
				proc = _MATCH_PROCS.pop(request_info["id"], None)
				if proc is not None and proc.poll() is None:
					proc.terminate()
				_SERVERS.pop(request_info["id"], None)
				_save_registry_locked()
			self._write_json(
				HTTPStatus.GATEWAY_TIMEOUT,
				{"ok": False, "error": "match server did not start in time"},
			)
			return

		server_info["is_public"] = request_info["is_public"]
		server_info["has_password"] = request_info["has_password"]
		self._write_json(HTTPStatus.OK, {"ok": True, "server": server_info})

	def _handle_heartbeat(self) -> None:
		try:
			payload = _read_json(self)
			entry = _sanitize_heartbeat(payload, self, _extract_remote_ip(self))
		except ValueError as exc:
			self._write_json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
			return

		with _LOCK:
			existing = _SERVERS.get(entry["id"], {})
			entry["is_public"] = bool(existing.get("is_public", entry["is_public"]))
			entry["has_password"] = bool(existing.get("has_password", entry["has_password"]))
			_SERVERS[entry["id"]] = entry
			_cleanup_locked()
			_save_registry_locked()

		self._write_json(HTTPStatus.OK, {"ok": True, "server": _public_server(entry)})

	def _handle_unregister(self) -> None:
		try:
			payload = _read_json(self)
		except ValueError as exc:
			self._write_json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
			return

		server_id = str(payload.get("id", "")).strip()
		if server_id == "":
			self._write_json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": "missing server id"})
			return

		with _LOCK:
			proc = _MATCH_PROCS.pop(server_id, None)
			if proc is not None and proc.poll() is None:
				proc.terminate()
			_SERVERS.pop(server_id, None)
			_save_registry_locked()

		self._write_json(HTTPStatus.OK, {"ok": True, "id": server_id})


def main() -> None:
	_load_registry()
	server = ThreadingHTTPServer((HOST, PORT), LobbyRegistryHandler)
	print("Power Soccer lobby registry listening on %s:%d" % (HOST, PORT), flush=True)
	server.serve_forever()


if __name__ == "__main__":
	main()
