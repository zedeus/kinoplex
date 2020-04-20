import jswebsockets, protocol, dom, patty, web_client, plyr

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
  loading = false
  reloading = false
  authenticated = false

proc syncTime(time: float) =
  let diff = abs(player.currentTime - time)
  if diff > 1 and diff != 0:
    player.currentTime = time

proc syncPlaying(playing: bool) =
  player.togglePlay(playing)

proc setState(playing: bool, time: float) =
  syncPlaying(playing)
  syncTime(time)n

proc showEvent(s: string) =
  w.alert(s)

server.ws = newWebSocket("ws://" & server.host)

server.ws.onOpen = proc (e:dom.Event) =
  server.ws.send($(%Auth($name, $password)))

server.ws.onMessage = proc (e:MessageEvent) =
  let event = unpack($e.data)
  match event:
    Joined(_, newRole):
      if not authenticated:
        if newRole != user:
          role = newRole
          showEvent($role)
        else:
          showEvent("Welcome to kinoplex!")
          if password.len > 0 and newRole == user:
            showEvent("Admin authentication failed")
        authenticated = true
        
    Message(msg):
      debugEcho msg
    State(playing, time):
      setState(playing, time)
    _: discard

server.ws.onClose = proc (e:CloseEvent) =
  close server.ws
  echo "Connection closed"
