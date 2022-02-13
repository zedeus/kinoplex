import ../config_utils

type
  Config* = object
    address*: string
    useTls*: bool
    username*: string
    password*: string
    mpvPath*: string

proc getConfig*(): Config =
  let cfg = loadConfig("mpv_client.conf")

  Config(
    address: cfg.get("Server", "address", "localhost:9001/ws"),
    useTls: cfg.get("Server", "useTLS", false),
    username: cfg.get("User", "username", "guest"),
    password: cfg.get("User", "password", ""),
    binPath: cfg.get("mpv", "binPath", "mpv")
  )
