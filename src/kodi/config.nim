import ../config_utils

type
  Config* = object
    address*: string
    useTls*: bool
    username*: string
    password*: string
    kodiAuth*: string
    kodiHost*: string

proc getConfig*(): Config =
  let cfg = loadConfig("kodi_client.conf")

  Config(
    address: cfg.get("Server", "address", "localhost:9001/ws"),
    useTls: cfg.get("Server", "useTLS", false),
    username: cfg.get("User", "username", "guest"),
    password: cfg.get("User", "password", ""),
    kodiAuth: cfg.get("Kodi", "auth", "kodi:kodi"),
    kodiHost: cfg.get("Kodi", "host", "localhost:9090")
  )
