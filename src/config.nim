import strformat, os, strutils, sequtils, sugar, parsecfg
export parsecfg

let configDir = getConfigDir() / "kinoplex"

let configPaths = [
  getCurrentDir(),
  getAppDir(),
  configDir
]

proc writeSampleConfig*(filename: string) =
  var cfg = newConfig()

  if filename == "client.conf":
    cfg.setSectionKey("client", "username", "kinoplexUser")
    cfg.setSectionKey("client", "password", "adminPassword")
    cfg.setSectionKey("client", "address", "kino.example.com/ws")
    cfg.setSectionKey("client", "useTLS", "True")
  elif filename == "server.conf":
    cfg.setSectionKey("server", "port", "9001")
    cfg.setSectionKey("server", "password", "adminPassword")
    cfg.setSectionKey("server", "websocketPath", "/ws")
    cfg.setSectionKey("server", "pauseOnLeave", "True")
    cfg.setSectionKey("server", "pauseOnChange", "False")

  discard existsOrCreateDir(configDir)

  cfg.writeConfig(configDir / filename)
  stderr.write(&"Wrote sample config to {configDir / filename}\nEdit it before using kinoplex\n")

  quit 1

proc getConfig*(filename: string): Config =
  var filepaths = configPaths.filter(n => fileExists(n / filename))

  if filepaths.len == 0:
    writeSampleConfig(filename)

  let path = filepaths[0] / filename

  echo &"Using config file located at {path}"
  return loadConfig(path)

proc getSectionBool*(cfg: Config, section, key: string): bool =
  let val = cfg.getSectionValue(section, key)
  if val.len == 0:
    return false

  return val.parseBool
