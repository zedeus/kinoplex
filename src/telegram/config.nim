import ../config_utils

type
  Config* = object
    token*: string

proc getConfig*(): Config =
  let cfg = loadConfig("telegram.conf")

  Config(
    token: cfg.get("Bot", "token", "SUPER_SECRET_TOKEN"),
  )
