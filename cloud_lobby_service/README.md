# Power Soccer Cloud Match Service

This service does two jobs:

- it lists active cloud matches for `Find Server`
- it launches real headless Godot dedicated servers on the Oracle machine for `Create Cloud Server`

That means the Oracle machine becomes the actual game server. Players connect directly to Oracle as clients, so your existing prediction, reconciliation, and lag smoothing still apply.

## Endpoints

- `GET /health`
- `GET /servers`
- `POST /create-match`
- `POST /heartbeat`
- `POST /unregister`

## What `create-match` Does

1. Picks a free UDP port on Oracle
2. Starts a headless Godot server process on that port
3. Waits for that server to heartbeat back
4. Returns the match `ip`, `port`, and metadata to the requesting client

## Oracle Linux 9 Setup

1. Install Python:

```bash
sudo dnf install -y python3
```

2. Copy `server.py`, your exported Linux dedicated build, and the service file to Oracle.

Recommended layout:

```bash
/home/opc/power-soccer/
  server.py
  power-soccer-server.x86_64
```

Your current Linux dedicated export uses `embed_pck=true`, so the server binary can run by itself. If you change the export preset back to a separate `.pck`, keep the `.pck` beside `power-soccer-server.x86_64`.

3. Open firewall ports:

```bash
sudo firewall-cmd --permanent --add-port=3000/tcp
sudo firewall-cmd --permanent --add-port=24565-24650/udp
sudo firewall-cmd --reload
```

4. Make the dedicated server executable:

```bash
chmod +x /home/opc/power-soccer/power-soccer-server.x86_64
```

5. Set the important environment variables:

- `POWER_SOCCER_PUBLIC_HOST`
  Example: `140.245.210.219` or your Oracle DNS name
- `POWER_SOCCER_SERVER_EXE`
  Example: `/home/opc/power-soccer/power-soccer-server.x86_64`
- `POWER_SOCCER_SERVER_WORKDIR`
  Example: `/home/opc/power-soccer`

6. Start the service manually for first testing:

```bash
cd /home/opc/power-soccer
POWER_SOCCER_PUBLIC_HOST=140.245.210.219 \
POWER_SOCCER_SERVER_EXE=/home/opc/power-soccer/power-soccer-server.x86_64 \
POWER_SOCCER_SERVER_WORKDIR=/home/opc/power-soccer \
python3 server.py
```

`server.py` must be the always-running listener. The Godot client cannot start `server.py` if nothing is already listening on the Oracle machine; `Create Server` sends `POST /create-match` to this service, and then this service starts `power-soccer-server.x86_64`.

## Manual API Tests

Health:

```bash
curl http://YOUR_ORACLE_PUBLIC_IP:3000/health
```

Create a dedicated match:

```bash
curl -X POST http://YOUR_ORACLE_PUBLIC_IP:3000/create-match \
  -H "Content-Type: application/json" \
  -d '{"name":"Test Cloud Match","is_public":true,"has_password":false}'
```

List matches:

```bash
curl http://YOUR_ORACLE_PUBLIC_IP:3000/servers
```

## systemd

Copy the service file:

```bash
sudo cp cloud_lobby_service/power-soccer-cloud.service /etc/systemd/system/
```

Reload and enable:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now power-soccer-cloud.service
```

Check logs:

```bash
sudo systemctl status power-soccer-cloud.service
journalctl -u power-soccer-cloud.service -f
```

## Important Notes

- This is the dedicated-server route, not peer hosting.
- The match creator is just another client.
- No home NAT traversal is needed for players.
- Oracle must have the game UDP ports open.
- Passwords are still metadata only in the current game code. The service stores the flag, but the game does not yet enforce password validation on join.
