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

proc syncTime(time: float) =
  let diff = abs(player.currentTime - time)
  if role == user:
    if diff > 1 and diff != 0:
      player.currentTime = time
  server.time = time

proc syncPlaying(playing: bool) =
  player.togglePlay(playing)
  server.playing = playing

proc syncIndex(index: int) =
  if index == -1: return
  if index != server.index and  server.playlist.len > 0:
    player.source = newSource(server.playlist[index])

proc setState(playing: bool; time: float) =
  syncPlaying(playing)
  syncTime(time)

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
          showEvent($role)
        else:
          showEvent("Welcome to kinoplex!")
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
      syncIndex(index)
    PlaylistClear:
      server.playlist = @[]
      setState(false, 0.0)
      showEvent("Playlist Cleared")
    Error(reason):
      window.alert(reason)
    _: discard

proc wsOnClose(e: CloseEvent) =
  player.destroy()
  close server.ws
  showEvent("Connection closed")

proc wsInit() =
  server.ws = newWebSocket("ws://" & server.host)
  server.ws.onOpen = wsOnOpen
  server.ws.onClose = wsOnClose
  server.ws.onMessage = wsOnMessage

proc createDom(): VNode =
  result = buildHtml(tdiv):
    tdiv(class="kinobox"):
      video(id="player", playsinline="", controls="")
    tdiv(class="kinochat"):
      for msg in messages:
        text msg
        br()
      tdiv(class = "messageBox"):
        input(class = "input", id = "messageInput", onkeyupenter = sendMessage)
        button(onclick = sendMessage):
          text "Send"

proc postRender =
  if player == nil:
    player = newPlyr(document.getElementById("player"))
  if server.ws == nil:
    wsInit()

setRenderer createDom, "ROOT", postRender
setForeignNodeId "player"
