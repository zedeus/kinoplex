import dom, jswebsockets, protocol

type
  Server = object
    ws: WebSocket
    host: string
    playlist: seq[string]
    index: int
    playing: bool
    time: float

  Plyr = object
    source: int
let
  w = dom.window
  d = dom.document
  
var
  server = Server(host: "127.0.0.1:9001/ws")
  name = "IDF"
  password = "1337"
  messages: seq[string]
  loading = false
  reloading = false

proc player {.importc: "player".}
