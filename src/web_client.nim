import jswebsockets, protocol, patty, plyr, dom, strformat
include karax / prelude

type
  Server = object
    ws: WebSocket
    host: string
    playlist: seq[string]
    index: int
    playing: bool
    time: float

var
  player: Plyr
  server = Server(host: "127.0.0.1:9001/ws")
  name = window.prompt("Enter username: ", "guest")
  password = window.prompt("Enter password (or leave empty):", "")
  role = user
  loading = false
  reloading = false
  authenticated = false
  messages: seq[string]

proc send(s: Server; data: protocol.Event) =
  server.ws.send($(%data))

proc syncTime() =
  let diff = abs(player.currentTime - server.time)
  if role != admin:
    if diff > 1 and diff != 0:
      player.currentTime = server.time

proc setState(playing: bool; time: float) =
  server.time = time
  syncTime()
  server.playing = playing
  player.togglePlay(playing)

proc addMessage(s: string) =
  messages.add(s)
  redraw()

proc sendMessage() =
  let
    input = document.getElementById("messageInput")
    msg = $input.value
  if msg.len == 0: return
  if msg[0] != '/':
    server.send(Message(msg))
    addMessage(&"<{name}>{msg}")
    input.value = ""

proc showEvent(s: string) =
  addMessage(s)

proc wsOnOpen(e: dom.Event) =
  server.send(Auth($name, $password))

proc wsOnMessage(e: MessageEvent) =
  let event = unpack($e.data)
  match event:
    Joined(newUser, newRole):
      if not authenticated:
        if newRole != user:
          role = newRole
          showEvent(&"Welcome to the kinoplex, {role}!")
        else:
          showEvent("Welcome to the kinoplex!")
        if password.len > 0 and newRole == user:
          showEvent("Admin authentication failed")
        authenticated = true
      else:
        showEvent(&"{newUser} joined as {$newRole}")
    Left(name):
      showEvent(&"{name} left")
    Message(msg):
      showEvent(msg)
    State(playing, time):
      setState(playing, time)
    PlaylistLoad(urls):
      server.playlist = urls
    PlaylistAdd(url):
      server.playlist.add(url)
    PlaylistPlay(index):
      player.source = server.playlist[index]
    PlaylistClear:
      server.playlist = @[]
      setState(false, 0.0)
      showEvent("Playlist Cleared")
    Error(reason):
      window.alert(reason)
    _: discard

proc wsOnClose(e: CloseEvent) =
  close server.ws
  showEvent("Connection closed")

proc wsInit() =
  server.ws = newWebSocket("ws://" & server.host)
  server.ws.onOpen = wsOnOpen
  server.ws.onClose = wsOnClose
  server.ws.onMessage = wsOnMessage

proc createDom(): VNode =
  result = buildHtml(tdiv):
    tdiv(class="kinochat"):
      tdiv(class="messageBox"):
        for msg in messages:
          text msg
          br()
      input(class="messageInput", onkeyupenter=sendMessage)
    tdiv(class="kinobox"):
      video(id="player", playsinline="", controls="")

proc postRender =
  if player == nil:
    player = newPlyr(document.getElementById("player"))
  if server.ws == nil:
    wsInit()

setRenderer createDom, "ROOT", postRender
setForeignNodeId "player"

discard window.setInterval(syncTime, 200)
