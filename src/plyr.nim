import dom, strutils, uri, jsffi
export jsffi

type
  Plyr* = ref object of JsObject
  Src = ref object
    src, `type`, provider: cstring
    size: int
  Track = ref object
    kind, label, srclang, src: cstring
    default: bool
  PlyrSource = ref object
    `type`, title, poster: cstring
    sources: seq[Src]
    tracks: seq[Track]

proc newPlyr*(id: cstring): Plyr {.importcpp: "new Plyr(#)".}

proc `source=`*(p: Plyr; url: string) =
  let u = parseUri(url)
  let host = u.hostname
  if "youtu" in host or "invidio" in host:
    var src =
      if u.path == "/watch":
        u.query.split("v=")[^1].split("&")[0]
      else:
        u.path
    p.source = PlyrSource{ `type`: "video", sources: @[Src{ src: src, provider: "youtube" }] }
  elif "vimeo" in host:
    p.source = PlyrSource{ `type`: "video", sources: @[Src{ src: u.path[1..^1], provider: "vimeo" }] }
  else:
    p.source = PlyrSource{ `type`: "video", sources: @[Src{ src: url }] }
    
