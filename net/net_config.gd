# NetConfig.gd
class_name NetConfig

extends Node

const PORT = 24565              # ENet server port
const DISCOVERY_PORT = 24566    # UDP discovery port (separate!)
const BROADCAST_IP = "255.255.255.255"
const DISCOVERY_TIMEOUT = 5.0
const BROADCAST_INTERVAL = 1.0

const CLOUD_SERVER_URL = "https://mygame.com/servers"
