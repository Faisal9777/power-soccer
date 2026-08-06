require("dotenv").config({ path: __dirname + "/.env2" });
const express = require("express");
const { spawn } = require("child_process");
const crypto = require("crypto");
const { get } = require("http");
const { OAuth2Client } = require("google-auth-library");
const jwt = require("jsonwebtoken");
const Database = require("better-sqlite3");

const db = new Database("players.db");
//Database Setup and functions
db.exec(`
CREATE TABLE IF NOT EXISTS players (
    player_id INTEGER PRIMARY KEY AUTOINCREMENT,
    google_sub TEXT NOT NULL UNIQUE,
    player_tag TEXT NOT NULL UNIQUE,
    player_name TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_login DATETIME DEFAULT CURRENT_TIMESTAMP
);
`);

const getPlayerByGoogleSub = db.prepare(`
SELECT *
FROM players
WHERE google_sub = ?
`);

const createPlayer = db.prepare(`
INSERT INTO players (
    google_sub,
    player_tag,
    player_name
)
VALUES (?, ?, ?)
`);

const updateLastLogin = db.prepare(`
UPDATE players
SET last_login = CURRENT_TIMESTAMP
WHERE player_id = ?
`);

const getPlayerById = db.prepare(`
SELECT *
FROM players
WHERE player_id = ?
`);

const ServerPhase = Object.freeze({
  STARTING: "starting",
  RUNNING: "running",
  STOPPING: "stopping",
  STOPPED: "stopped",
  ERROR: "error"
});

const app = express();
app.use(express.json());

// ----------------------------------------
// 🔐 AUTHENTICATION CONFIG & STATE
// ----------------------------------------
const GOOGLE_CLIENT_IDS = [
    process.env.DESKTOP_CLIENT_ID,
    process.env.WEB_CLIENT_ID
];

const DESKTOP_CLIENT_ID = process.env.DESKTOP_CLIENT_ID

const GOOGLE_CLIENT_SECRET = process.env.GOOGLE_CLIENT_SECRET;
if (!process.env.JWT_SECRET) {
    throw new Error("JWT_SECRET missing");
}
const JWT_SECRET = process.env.JWT_SECRET;

const oauthClient = new OAuth2Client(DESKTOP_CLIENT_ID, GOOGLE_CLIENT_SECRET);



// 🔧 GAME SERVER CONFIG
const SERVER_PATH = process.env.POWER_SOCCER_SERVER_EXE || process.env.SERVER_PATH;
const SERVER_CWD = process.env.POWER_SOCCER_SERVER_WORKDIR || process.env.SERVER_CWD;
const BASE_PORT = Number(process.env.POWER_SOCCER_MATCH_PORT_START || process.env.BASE_PORT || 24565);
const PUBLIC_IP = process.env.POWER_SOCCER_PUBLIC_HOST || process.env.PUBLIC_IP || "127.0.0.1";
const MAX_SERVERS = 10;
const TTL_SEC = Number(process.env.POWER_SOCCER_TTL_SEC || 12);

const ResponseType = Object.freeze({
    NEW_SERVER: 0,
    REJOIN: 1,
    REJECTED: 2
});

const killTimers = new Map();
const IDLE_TIMEOUT_MS = 5 * 60 * 1000;
const DEFAULT_MAX_PLAYERS = 4;

// 📦 State
let servers = new Map();
let serversByPort = new Map();
let playersInLobbies = new Map();
let pendingServers = new Map();
let usedPorts = new Set();

const HEARTBEAT_TIMEOUT = 10000;
const CLEANUP_INTERVAL = 5000;

if (!SERVER_PATH || !SERVER_CWD || !BASE_PORT || !PUBLIC_IP) {
    throw new Error("Missing environment variables");
}

function authenticatePlayer(req, res, next) {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
        return res.status(401).json({ error: "Bearer token missing." });
    }

    const token = authHeader.split(" ")[1];

    try {
        const decoded = jwt.verify(token, JWT_SECRET);
        const player = getPlayerById.get(decoded.player_id);

        if (!player) {
            return res.status(401).json({ error: "Player no longer exists." });
        }

        req.player = decoded;
        req.playerId = decoded.player_id;
        next();
    } catch (err) {
        return res.status(401).json({ error: "Invalid or expired session token." });
    }
}

app.post("/api/auth/login", async (req, res) => {
    const { code, redirect_uri } = req.body;

    if (!code) {
        return res.status(400).json({ error: "Authorization code missing." });
    }

    try {
        const { tokens } = await oauthClient.getToken({
            code,
            redirect_uri: redirect_uri || "http://127.0.0.1:8080"
        });

        const ticket = await oauthClient.verifyIdToken({
            idToken: tokens.id_token,
            audience: GOOGLE_CLIENT_IDS
        });
        const payload = ticket.getPayload();

        const googleSub = payload.sub;
        const googleName = payload.name || "Player";

        let player = getPlayerByGoogleSub.get(googleSub);

        if (!player) {
            const playerTag = crypto.randomUUID();
            const result = createPlayer.run(googleSub, playerTag, googleName);
            player = getPlayerById.get(result.lastInsertRowid);
            console.log(`Created new account: player_id=${player.player_id}`);
        } else {
            updateLastLogin.run(player.player_id);
            player = getPlayerById.get(player.player_id);
        }

        const sessionToken = jwt.sign(
            {
                player_id: player.player_id,
                player_tag: player.player_tag,
                player_name: player.player_name
            },
            JWT_SECRET,
            { expiresIn: "30d" }
        );

        return res.json({
            session_token: sessionToken,
            player_id: player.player_id,
            player_tag: player.player_tag,
            player_name: player.player_name
        });
    } catch (error) {
        console.error("Authentication error:", error);
        return res.status(401).json({ error: "Invalid google authorization code." });
    }
});

app.post("/api/auth/login-mobile", async (req, res) => {
    const { id_token } = req.body;

    if (!id_token) {
        return res.status(400).json({ error: "Missing id_token" });
    }

    try {
        const ticket = await oauthClient.verifyIdToken({
            idToken: id_token,
            audience: GOOGLE_CLIENT_IDS
        });

        const payload = ticket.getPayload();
        const googleSub = payload.sub;
        const googleName = payload.name || "Player";

        let player = getPlayerByGoogleSub.get(googleSub);
        if (!player) {
            console.log("Rejected unregistered user:", googleSub);
            return res.status(403).json({ error: "User is not registered." });
        }

        updateLastLogin.run(player.player_id);
        player = getPlayerById.get(player.player_id);

        const sessionToken = jwt.sign(
            {
                player_id: player.player_id,
                player_tag: player.player_tag,
                player_name: player.player_name
            },
            JWT_SECRET,
            { expiresIn: "30d" }
        );

        return res.json({
            session_token: sessionToken,
            player_id: player.player_id,
            player_tag: player.player_tag,
            player_name: player.player_name
        });
    } catch (err) {
        console.error("Mobile auth error:", err);
        return res.status(401).json({ error: "Invalid ID token" });
    }
});

app.get("/api/auth/verify", (req, res) => {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
        return res.status(401).json({ error: "Bearer token missing." });
    }

    const token = authHeader.split(" ")[1];

    try {
        const decoded = jwt.verify(token, JWT_SECRET);
        const player = getPlayerById.get(decoded.player_id);

        if (!player) {
            return res.status(401).json({ error: "Player no longer exists." });
        }

        return res.json({
            player_id: player.player_id,
            player_tag: player.player_tag,
            player_name: player.player_name
        });
    } catch (err) {
        return res.status(401).json({ error: "Invalid or expired session token." });
    }
});

setInterval(() => {
    const now = Date.now();

    for (const [id, server] of servers.entries()) {
        if (now - server.lastSeen > HEARTBEAT_TIMEOUT) {
            console.log(`Server ${server.id} timed out`);
            if (server.process && !server.process.killed) {
                server.process.kill();
            }
            usedPorts.delete(server.port);
            servers.delete(id);
            serversByPort.delete(server.port);
            if (killTimers.has(id)) {
                clearTimeout(killTimers.get(id));
                killTimers.delete(id);
            }

            for (const [playerId, serverId] of playersInLobbies.entries()) {
                if (serverId === id) {
                    playersInLobbies.delete(playerId);
                }
            }
        }
    }
}, CLEANUP_INTERVAL);

function getFreePort() {
    for (let i = 0; i < MAX_SERVERS; i++) {
        let port = BASE_PORT + i;
        if (!usedPorts.has(port)) {
            usedPorts.add(port);
            return port;
        }
    }
    return null;
}

function findIdleServer() {
    console.log("Checking for idle servers to reuse...");
    for (const [id, server] of servers.entries()) {
        if (killTimers.has(id)) {
            removeServerKillTimer(id);
            console.log(`Reusing idle server ${id}`);
            return server;
        }
    }
}

async function createServer(isPublic = false, playerName = "Player") {
    let server = findIdleServer();
    if (server) {
        console.log(`Reusing idle server on port ${server.port}`);
        return server;
    }

    const port = getFreePort();
    console.log(`Attempting to create server on port ${port}`);
    if (!port) return null;

    const id = crypto.randomBytes(16).toString("hex");
    console.log(`Generated lobby ID: ${id}`);

    server = {
        id,
        port,
        ip: PUBLIC_IP,
        process: null,
        status: ServerPhase.STARTING,
        lastSeen: Date.now(),
        players: 0,
        maxPlayers: DEFAULT_MAX_PLAYERS,
        serverInfo: {}
    };

    servers.set(server.id, server);
    serversByPort.set(server.port, server);

    let proc;
    try {
        proc = await createProcess(id, port, isPublic, playerName);
        server.process = proc;
    } catch (err) {
        console.error(`Failed to start server process for ${id}:`, err);
        cleanupServer(port);
        throw err;
    }

    proc.stdout.on("data", d => console.log(`[${port}] ${d}`));
    proc.stderr.on("data", d => console.error(`[${port} ERROR] ${d}`));

    proc.on("exit", () => {
        console.log(`Server ${port} exited`);
        cleanupServer(port);
    });

    return server;
}

async function createProcess(lobbyId, port, isPublic = false, playerName = "Player") {
    return new Promise((resolve, reject) => {
        console.log(`Spawning dedicated server process with lobby ID: ${lobbyId}, port: ${port}`);
        const proc = spawn(SERVER_PATH, [
            "--headless",
            "--server",
            "--id", lobbyId.toString(),
            "--port", port.toString(),
            "--public", isPublic.toString(),
            "--player_name", playerName
        ], { cwd: SERVER_CWD });

        if (!proc || !proc.pid) {
            console.log("Failed to start server process");
        }

        const timeout = setTimeout(() => {
            if (pendingServers.has(lobbyId)) {
                pendingServers.delete(lobbyId);
                console.error("DELETE pending server\nReason: Startup timeout fired\nLobby ID: " + lobbyId);
                console.error(`Current Map size: ${pendingServers.size}`);
                console.error(`Current Keys: ${[...pendingServers.keys()].join(", ")}`);
                reject(new Error("Server never became ready"));
            }
        }, 15000);

        pendingServers.set(lobbyId, { resolve, proc, timeout, port });
        console.log("ADD pending server\nLobby ID: " + lobbyId + "\nCurrent Map size: " + pendingServers.size + "\nCurrent Keys: " + [...pendingServers.keys()].join(", "));

        proc.stdout.on("data", (data) => {
            const msg = data.toString().trim();
            console.log(`[SERVER ${lobbyId}] ${msg}`);
        });

        proc.stderr.on("data", (data) => {
            console.error(`[SERVER ${lobbyId} ERROR] ${data.toString().trim()}`);
        });

        proc.on("exit", (code, signal) => {
            console.log(`[SERVER ${lobbyId}] exited with code ${code}, signal ${signal}`);
        });

        proc.on("error", (err) => {
            console.error(`[SERVER ${lobbyId}] failed to start:`, err);
        });

    });
}

function getFreeServer() {
    for (const server of servers.values()) {
        if (server.players === 0) {
            return server;
        }
    }
    return null;
}

function cleanupServer(port) {
    const server = serversByPort.get(port);
    if (!server) return;

    const id = server.id;
    if (server.process && !server.process.killed && server.process.exitCode === null && server.process.signalCode === null) {
        server.process.kill();
    }

    servers.delete(id);
    serversByPort.delete(port);
    usedPorts.delete(port);
    if (killTimers.has(id)) {
        clearTimeout(killTimers.get(id));
        killTimers.delete(id);
    }

    for (const [playerId, serverId] of playersInLobbies.entries()) {
        if (serverId === id) {
            playersInLobbies.delete(playerId);
        }
    }
}

function removeServerKillTimer(id) {
    clearTimeout(killTimers.get(id));
    killTimers.delete(id);
    console.log(`Server ${id} is active again, removed from kill list`);
}

function getServerStatus(serverInfo) {
    return (serverInfo?.players_connected ?? 0) > 0;
}

function checkIfPlayerIsInLobby(playerId) {
    console.log(`Checking if player ${playerId} is already in a lobby...`);
    if (!playerId) return null;

    const serverId = playersInLobbies.get(String(playerId));
    if (serverId) {
        return servers.get(String(serverId)) || null;
    }
    return null;
}

app.post("/create-lobby", authenticatePlayer, async (req, res) => {
    try {
        const playerId = req.playerId;
        const isPublic = req.body.is_public;
        const playerName = req.body.player_name 
        let server = checkIfPlayerIsInLobby(playerId);

        if (server) {
            console.log(`Player ${playerId} is already in a lobby, returning existing server`);
            return res.json({ ip: server.ip, port: server.port, response: ResponseType.REJOIN });
        }

        server = getFreeServer();
        if (!server) {
            server = await createServer(isPublic, playerName);
        }

        if (!server) {
            return res.status(503).json({ error: "No lobby available" });
        }

        return res.json({ ip: server.ip, port: server.port, response: ResponseType.NEW_SERVER });
    } catch (err) {
        console.error(err);
        return res.status(500).json({ error: "Failed to find a lobby" });
    }
});

// Alias for server.py compatibility
app.post("/create-match", authenticatePlayer, async (req, res) => {
    try {
        const playerId = req.playerId;
        let server = checkIfPlayerIsInLobby(playerId);

        if (server) {
            return res.json({
                ok: true,
                server: {
                    id: server.id,
                    name: server.serverInfo?.name || server.serverInfo?.server_name || "Match",
                    ip: server.ip,
                    port: server.port,
                    players_connected: server.players,
                    lobby_size: server.maxPlayers,
                    is_public: server.serverInfo?.is_public !== false,
                    has_password: server.serverInfo?.has_password || false,
                    state: server.status,
                    source: "cloud",
                    ping: -1
                },
                response: ResponseType.REJOIN
            });
        }

        server = getFreeServer();
        if (!server) {
            server = await createServer();
        }

        if (!server) {
            return res.status(503).json({ ok: false, error: "No lobby available" });
        }

        const serverInfo = {
            id: server.id,
            name: req.body.name || "Match",
            ip: server.ip,
            port: server.port,
            players_connected: 0,
            lobby_size: 0,
            is_public: req.body.is_public !== false,
            has_password: req.body.has_password || false,
            state: server.status,
            source: "cloud",
            ping: -1
        };

        return res.json({ ok: true, server: serverInfo, response: ResponseType.NEW_SERVER });
    } catch (err) {
        console.error(err);
        return res.status(500).json({ ok: false, error: "Failed to create match" });
    }
});

app.get("/lobbies", authenticatePlayer, (req, res) => {
    const playerId = req.playerId;
    const server = checkIfPlayerIsInLobby(playerId);

    if (server) {
        console.log(`Player ${playerId} is already in a lobby, returning existing server`);
        return res.json({ ...server.serverInfo, ip: server.ip, port: server.port, response: ResponseType.REJOIN });
    }

    const available = [...servers.values()].filter(s => s.status === ServerPhase.RUNNING);

    res.json(available.map(s => ({
        ...s.serverInfo,
        id: s.id,
        ip: s.ip,
        port: s.port
    })));
});

// Alias for server.py compatibility
app.get("/servers", authenticatePlayer, (req, res) => {
    const available = [...servers.values()].filter(s => s.status === ServerPhase.RUNNING);
    res.json({
        servers: available.map(s => ({
            id: s.id,
            name: s.serverInfo?.name || s.serverInfo?.server_name || "Unnamed Server",
            ip: s.ip,
            port: s.port,
            players_connected: s.serverInfo?.players_connected || s.players || 0,
            lobby_size: s.serverInfo?.lobby_size || s.maxPlayers || 0,
            is_public: s.serverInfo?.is_public !== false,
            has_password: s.serverInfo?.has_password || false,
            state: s.serverInfo?.state || s.status,
            source: "cloud",
            ping: -1
        }))
    });
});

app.post("/unregister", (req, res) => {
    const { id } = req.body;
    if (!id) return res.status(400).json({ ok: false, error: "missing server id" });

    const server = [...servers.values()].find(s => s.id === id);
    if (server) {
        cleanupServer(server.port);
    }
    res.json({ ok: true, id });
});

app.post("/join-lobby", authenticatePlayer, (req, res) => {
    const { port } = req.body;
    const playerId = req.playerId;
    const server = serversByPort.get(Number(port));

    if (!server || server.status !== ServerPhase.RUNNING) {
        return res.status(404).json({ error: "Server not found" });
    }

    if (server.players >= server.maxPlayers) {
        return res.status(403).json({ error: "Lobby full" });
    }

    playersInLobbies.set(String(playerId), server.id);

    res.json({ ip: PUBLIC_IP, port: server.port });
});

app.post("/leave-lobby", authenticatePlayer, (req, res) => {
    const { port } = req.body;
    const playerId = req.playerId;
    const server = serversByPort.get(Number(port));

    if (server) {
        playersInLobbies.delete(String(playerId));
    }

    res.json({ success: true });
});

app.post("/player-joined", authenticatePlayer, (req, res) => {
    const { server_id } = req.body;
    const playerId = req.playerId;
    const serverId = String(server_id);

    if (!serverId || !servers.has(serverId)) {
        return res.status(404).json({ error: "server_not_found" });
    }

    playersInLobbies.set(String(playerId), serverId);
    console.log(`player ${playerId} joined server ${serverId}`);
    res.json({ ok: true });
});

app.post("/player-disconnected", authenticatePlayer, (req, res) => {
    const { server_id } = req.body;
    const playerId = req.playerId;
    const serverId = String(server_id);

    if (!serverId || !servers.has(serverId)) {
        return res.status(404).json({ error: "server_not_found" });
    }

    playersInLobbies.delete(String(playerId));
    console.log(`player ${playerId} left server ${serverId}`);
    res.json({ ok: true });
});

app.post("/heartbeat", (req, res) => {
    const { id } = req.body;
    console.log("Heartbeat received");
    console.log("Heartbeat ID: " + id);
    if (!id) return res.status(400).send("Missing id");

    console.log("Current pending keys: " + [...pendingServers.keys()].join(", "));
    console.log("pendingServers.has(id): " + pendingServers.has(id));

    if (pendingServers.has(id)) {
        const entry = pendingServers.get(id);
        pendingServers.delete(id);
        if (entry.timeout) {
            clearTimeout(entry.timeout);
        }
        console.log("DELETE pending server\nReason: Heartbeat matched pending entry\nLobby ID: " + id + "\nCurrent Map size: " + pendingServers.size + "\nRemaining Keys: " + [...pendingServers.keys()].join(", "));
        console.log(`createProcess resolved\nLobby ID: ${id}`);
        console.log(`Server ${id} is now READY`);
        const server = servers.get(id);
        if (server) {
            server.status = ServerPhase.RUNNING;
        }
        entry.resolve(entry.proc);
        return res.send("OK (registered)");
    }

    const server = servers.get(id);
    if (server) {
        server.lastSeen = Date.now();
        server.serverInfo = req.body;
        server.players = Number(req.body.players_connected ?? req.body.players?.length ?? 0);

        if (req.body.max_players) {
            server.maxPlayers = Number(req.body.max_players);
        }

        const isActive = getServerStatus(server.serverInfo);
        const playerIds = Array.isArray(req.body.players) ? req.body.players : [];

        for (const [playerId, assignedServerId] of [...playersInLobbies.entries()]) {
            if (assignedServerId === id) {
                playersInLobbies.delete(playerId);
            }
        }

        for (const playerId of playerIds) {
            playersInLobbies.set(String(playerId), id);
        }

        if (!isActive && !killTimers.has(id)) {
            const timer = setTimeout(() => {
                console.log(`Server ${id} idle too long, killing...`);
                killTimers.delete(id);
                cleanupServer(server.port);
            }, IDLE_TIMEOUT_MS);
            killTimers.set(id, timer);
            console.log(`Server ${id} marked for idle kill`);
        } else if (isActive && killTimers.has(id)) {
            removeServerKillTimer(id);
        }
    }

    res.json({ success: true });
});

app.get("/validate", authenticatePlayer, (req, res) => {
    res.json({ success: true, player_id: req.playerId });
});

app.get("/", (req, res) => res.send("Backend running"));

app.get("/health", (req, res) => {
    res.json({
        ok: true,
        active_servers: [...servers.values()].filter(s => s.status === ServerPhase.RUNNING).length,
        running_matches: servers.size,
        ttl_sec: TTL_SEC
    });
});

app.listen(3000, "0.0.0.0", () => {
    console.log("Backend running on 3000");
});