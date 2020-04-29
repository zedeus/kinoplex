import jswebsockets, protocol, patty, plyr, dom, strformat
include karax / prelude

type
  Server = object
    ws: WebSocket
    host: string
    playlist: seq[string]
    users: seq[string]
    index: int
    playing: bool
    time: float

  Msg = object
    name, text: kstring

  Tab = enum
    chatTab, usersTab, playlistTab

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
  activeTab = chatTab

proc send(s: Server; data: protocol.Event) =
  server.ws.send($(%data))

proc changeActiveTab(tab: Tab) =
  activeTab = tab
  
  var btnId: string
  case activeTab:
    of chatTab:
      btnId = "tabChat"
    of usersTab:
      btnId = "tabUsers"
    of playlistTab:
      btnId = "tabPlaylist"
  let elem = document.getElementById(btnId)
  for btn in document.getElementsByClassName("tabButton"):
    btn.class = "tabButton"
  elem.class = "tabButton activeTabButton"

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
  if activeTab != chatTab: changeActiveTab(chatTab)
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
    Clients(users):
      server.users = users
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
  if activeTab == chatTab:
    let box = document.getElementsByClassName("messageBox")[0]
    box.scrollTop = box.scrollHeight

proc showChat(): VNode =
  result = buildHtml(tdiv(class="messageBox")):
    for msg in messages:
      let class = if msg.name == "server": "Event" else: "Text"
      tdiv(class=("message" & class)):
        if class == "Text":
          tdiv(class="messageName"): text &"{msg.name}: "
          text msg.text

proc showUsers(): VNode =
  result = buildHtml(tdiv(class="usersBox")):
    if server.users.len > 0:
      for user in server.users:
        tdiv(class="userText"):
          text user & (if user == name: " (You)" else: "")
    else:
      text "No users. (That's weird, you're here tho)"

proc showPlaylist(): VNode =
  result = buildHtml(tdiv(class="playlistBox")):
    if server.playlist.len > 0:
        for i, play in server.playlist:
          tdiv(class="playText"):
            text &"{i} - {play}"
    else:
      text "Nothing is on the playlist yet. Here's some popcorn 🍿!"


proc tabClick(ev: dom.Event; n: VNode) =
  changeActiveTab(playlistTab)

proc createDom(): VNode =
  result = buildHtml(tdiv):
    tdiv(class="kinopanel"):
      tdiv(class="panelBox"):
        tdiv(class="tabsContainer"):
            button(class="tabButton", id="tabChat"):
              text "Chat"
              proc onclick() = changeActiveTab(chatTab)
            button(class="tabButton", id="tabUsers"):
              text "Users"
              proc onclick() = changeActiveTab(usersTab)
            button(class="tabButton", id="tabPlaylist"):
              text "Playlist"
              proc onclick() = changeActiveTab(playlistTab)
        case activeTab:
          of chatTab: showChat()
          of usersTab: showUsers()
          of playlistTab: showPlaylist()
      input(id="input", class="messageInput", onkeyupenter=sendMessage)
    tdiv(class="kinobox"):
      video(id="player", playsinline="", controls="", autoplay="")

proc postRender =
  if player == nil:
    player = newPlyr("#player")
  if server.ws == nil:
    wsInit()
  scrollToBottom()

setRenderer createDom, "ROOT", postRender
setForeignNodeId "player"

discard window.setInterval(syncTime, 200)
