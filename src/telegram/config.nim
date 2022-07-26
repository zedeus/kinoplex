import ../config_utils

type
  Config* = object
    address*: string
    useTls*: bool
    token*: string

proc getConfig*(): Config =
  let cfg = loadConfig("telegram.conf")

  Config(
    address: cfg.get("Server", "address", "localhost:9001/ws"),
    useTls: cfg.get("Server", "useTLS", false),
    token: cfg.get("Bot", "token", "SUPER_SECRET_TOKEN")
  )
