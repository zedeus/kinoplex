import strformat, os, strutils, sequtils, sugar, parsecfg
export parsecfg


let configDir = getConfigDir() / "kinoplex"

let configPaths = [
  getCurrentDir(),
  configDir
]

proc getConfig*(filenameBase: string): Config =
  var
    filename = filenameBase & ".conf"
    filepaths = configPaths.filter(n => fileExists(n & filename))

  if filepaths.len == 0:
    let defaultFile = configDir / filename

    var cfg = newConfig()

    if filenameBase == "client":
      cfg.setSectionKey("client", "username", "kinoplexUser")
      cfg.setSectionKey("client", "password", "adminPassword")
      cfg.setSectionKey("client", "address", "kino.example.com/ws")
      cfg.setSectionKey("client", "useTLS", "True")
    elif filenameBase == "server":
      cfg.setSectionKey("server", "port", "9001")
      cfg.setSectionKey("server", "password", "adminPassword")
      cfg.setSectionKey("server", "websocketPath", "/ws")
      cfg.setSectionKey("server", "pauseOnLeave", "True")
      cfg.setSectionKey("server", "pauseOnChange", "False")

    discard existsOrCreateDir(configDir)

    cfg.writeConfig(defaultFile)
    stderr.write(&"Wrote sample config to {defaultFile}\nedit it before using kinoplex\n")

    quit 1

  let filepath = filepaths[0] & filename

  echo &"Using config file located at {filepath}"

  loadConfig(filepath)

proc getSectionBool*(cfg: Config, section, key: string): bool =
  let val = cfg.getSectionValue(section, key)
  if val == "":
    return false

  return val.parseBool
