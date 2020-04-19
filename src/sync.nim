import plyr, jswebsockets, protocol, dom, patty

type
  Server = object
    ws: WebSocket
    host: string
    playlist: seq[string]
    index: int
    playing: bool
    time: float
    
let
  w = dom.window
  d = dom.document
  
var
  server = Server(host: "127.0.0.1:9001/ws")
  name = w.prompt("Enter username: ", "guest")
  password = w.prompt("Enter password (or leave empty):", "")
  role = user
  messages: seq[string]
  loading = false
  reloading = false

let player = newPlyr()


proc syncTime(time: float) =
  player.currentTime = time

proc syncPlaying(playing: bool) =
  player.togglePlay(playing)

proc setState(playing: bool, time: float) =
  syncPlaying(playing)
  syncTime(time)

proc showEvent(s: string) =
  w.alert(s)

server.ws = newWebSocket("ws://" & server.host)

server.ws.onOpen = proc (e:dom.Event) =
  server.ws.send($(%Auth($name, $password)))

server.ws.onMessage = proc (e:MessageEvent) =
  let event = unpack($e.data)
  match event:
    Joined(_, newRole):
      if newRole != user:
        role = newRole
        showEvent($role)
      else:
        showEvent("Welcome to kinoplex!")
      if password.len > 0 and newRole == user:
        showEvent("Admin authentication failed")
        
    Message(msg):
      echo msg
    State(playing, time):
      setState(playing, time)
    _: discard

server.ws.onClose = proc (e:CloseEvent) =
  close server.ws
  echo "Connection closed"
