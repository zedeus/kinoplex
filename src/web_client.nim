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

  Msg = object
    name, text: kstring

var
  player: Plyr
  server = Server(host: "127.0.0.1:9001/ws")
  name = window.prompt("Enter username: ", "guest")
  password = window.prompt("Enter password (or leave empty):", "")
  role = user
  loading = false
  reloading = false
  authenticated = false
  messages: seq[Msg]

proc send(s: Server; data: protocol.Event) =
  server.ws.send($(%data))

proc addMessage(m: Msg) =
  messages.add(m)
  redraw()

proc showMessage(name, text: string) =
  addMessage(Msg(name: name, text: text))

proc showEvent(text: string) =
  addMessage(Msg(name: "server", text: text))
  echo text

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

proc playIndex(index: int) =
  showEvent("Playing " & server.playlist[index])
  player.source = server.playlist[index]

proc sendMessage() =
  let
    input = document.getElementById("input")
    msg = $input.value
  if msg.len == 0: return
  if msg[0] != '/':
    input.value = ""
    addMessage(Msg(name: name, text: msg))
    server.send(Message($name, msg))

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
    Message(name, text):
      showMessage(name, text)
    State(playing, time):
      setState(playing, time)
    PlaylistLoad(urls):
      server.playlist = urls
    PlaylistAdd(url):
      server.playlist.add(url)
      if server.playlist.len == 1:
        playIndex(0)
    PlaylistPlay(index):
      playIndex(index)
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

proc scrollToBottom() =
  let box = document.getElementsByClassName("messageBox")[0]
  box.scrollTop = box.scrollHeight

proc createDom(): VNode =
  result = buildHtml(tdiv):
    tdiv(class="kinochat"):
      tdiv(class="messageBox"):
        for msg in messages:
          let class = if msg.name == "server": "Event" else: "Text"
          tdiv(class=("message" & class)):
            if class == "Text":
              tdiv(class="messageName"): text &"{msg.name}: "
            text msg.text
      input(id="input", class="messageInput", onkeyupenter=sendMessage)
    tdiv(class="kinobox"):
      video(id="player", playsinline="", controls="")

proc postRender =
  if player == nil:
    player = newPlyr("#player")
  if server.ws == nil:
    wsInit()
  scrollToBottom()

setRenderer createDom, "ROOT", postRender
setForeignNodeId "player"

discard window.setInterval(syncTime, 200)
