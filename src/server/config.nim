import ../config_utils

type
  Config* = object
    port*: int
    staticDir*: string
    wsPath*: string
    adminPassword*: string
    pauseOnChange*: bool
    pauseOnLeave*: bool

proc getConfig*(): Config =
  let cfg = loadConfig("server.conf")

  Config(
    port: cfg.get("Server", "port", 9001),
    staticDir: cfg.get("Server", "staticDir", "./static"),
    wsPath: cfg.get("Server", "wsPath", "/ws"),
    adminPassword: cfg.get("Server", "adminPassword", "1337"),
    pauseOnChange: cfg.get("Server", "pauseOnChange", true),
    pauseOnLeave: cfg.get("Server", "pauseOnLeave", false)
  )
