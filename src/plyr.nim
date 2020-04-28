import dom, strutils, uri

type
  Plyr* {.importc.} = ref object
    currentTime*: float

  Source* {.importc.} = object

proc newPlyr*(n: cstring): Plyr {.importcpp: "new Plyr(#)".}
proc togglePlay*(p: Plyr; status: bool) {.importcpp.}

proc newSource(url: cstring): Source
    {.importcpp: "{type:'video',sources:[{src:#}]}".}
proc newSourceProvider(url, pro: cstring): Source
    {.importcpp: "{type:'video',sources:[{src:#,provider:@}]}".}

proc `source=`(p: Plyr; s: Source) {.importcpp: "#.source = @".}

proc `source=`*(p: Plyr; url: string) =
  let u = parseUri(url)
  let host = u.hostname
  if "youtu" in host or "invidio" in host:
    var src = url
    if u.path == "/watch":
      src = u.query.split("v=")[^1].split("&")[0]
    else:
      src = u.path
    p.source = newSourceProvider(src, "youtube")
  elif "vimeo" in host:
    p.source = newSourceProvider(u.path[1..^1], "vimeo")
  else:
    p.source = newSource(url)
