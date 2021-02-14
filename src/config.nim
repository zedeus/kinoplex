import strformat, os, strutils, sequtils, sugar, parsecfg
export parsecfg

proc safeGetEnv(keyStr: string): string =
  let key = keyStr.toUpperAscii

  if not existsEnv(key):
    stderr.write(&"Could not find environment variable '{key}'\n")
    quit 1

  return getEnv(key)

proc getSectionBool*(cfg: Config, section, key: string): bool =
  let val = cfg.getSectionValue(section, key)
  if val == "":
    return false

  return val.parseBool

when defined(windows):
  const configPaths = @[
    r".\",
    r"%APPDATA%\",
    r"%HOMEPATH%\.config\kinoplex\",
    r"C:\"
  ]
else:
  let homePath = safeGetEnv("home").strip(leading = false, chars = {'/'})

  let configPaths = @[
    &"./",
    &"{homePath}/.config/kinoplex/",
    &"/etc/"
  ]

proc getConfig*(filenameBase: string): Config =
  var
    filename = filenameBase & ".conf"
    filepaths = configPaths.filter(n => fileExists(n & filename))

  if filepaths.len == 0:
    when defined(windows):
      let defaultFile = r"%HOMEPATH%\.config\kinoplex\{filename}"
    else:
      let defaultFile = &"{homePath}/.config/kinoplex/{filename}"

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
      
    cfg.writeConfig(defaultFile)
    stderr.write(&"Wrote sample config to {defaultFile}, make sure to edit it before using kinoplex\n")

    quit 1

  let filepath = filepaths[0] & filename

  echo &"Using config file located at {filepath}"

  loadConfig(filepath)
