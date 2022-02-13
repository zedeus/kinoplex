import std/[os, parsecfg, strutils, sequtils]

let configPaths = [
  getCurrentDir(),
  getAppDir(),
  getConfigDir() / "kinoplex"
]

proc loadConfig*(filename: string): Config =
  let paths = configPaths.filterIt(fileExists(it / filename))

  if paths.len == 0:
    echo "No config found"
    echo "Rename and modify ", filename.replace(".conf", ".example.conf")
    quit(1)

  let path = paths[0] / filename

  echo "Using config file located at ", path
  return parsecfg.loadConfig(path)

proc get*[T](config: Config; section, key: string; default: T): T =
  let val = config.getSectionValue(section, key)
  if val.len == 0: return default

  when T is int: parseInt(val)
  elif T is bool: parseBool(val)
  elif T is string: val

