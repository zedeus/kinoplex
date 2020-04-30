import jswebsockets, protocol, patty, plyr, dom, strformat, sequtils
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
  activeTab: Tab
  currentMovie: string

proc send(s: Server; data: protocol.Event) =
  server.ws.send($(%data))

proc switchTab(tab: Tab) =
  activeTab = tab
  var tabName: string
  case tab:
    of chatTab: tabName = "Chat"
    of usersTab: tabName = "Users"
    of playlistTab: tabName= "Playlist"
  let
    activeBtn = document.getElementById(&"btn{tabName}")
    activeTab = document.getElementById(&"kino{tabName}")
  for btn in document.getElementsByClassName("tabButton"):
    btn.class = "tabButton"
  activeBtn.class = "tabButton activeTabButton"
  for tab in document.getElementsByClassName("tabBox"):
    tab.style.display = "none"
  activeTab.style.display = "block"

proc addMessage(m: Msg) =
  messages.add(m)
  if activeTab == chatTab: redraw()

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

proc playIndex(index: int) =
  showEvent("Playing " & currentMovie)
  currentMovie = server.playlist[index]
  player.source = currentMovie
  if activeTab == playlistTab: redraw()

proc setState(playing: bool; time: float) =
  server.time = time
  syncTime()
  server.playing = playing
  player.togglePlay(playing)

proc sendMessage() =
  let
    input = document.getElementById("input")
    msg = $input.value
  if activeTab != chatTab: switchTab(chatTab)
  if msg.len == 0: return
  if msg[0] != '/':
    input.value = ""
    addMessage(Msg(name: name, text: msg))
    server.send(Message($name, msg))

proc authenticate(newUser: string; newRole: Role) =
  if newRole != user:
    role = newRole
    showEvent(&"Welcome to the kinoplex, {role}!")
  else:
    showEvent("Welcome to the kinoplex!")
    if password.len > 0 and newRole == user:
      showEvent("Admin authentication failed")
    authenticated = true

proc wsOnOpen(e: dom.Event) =
  server.send(Auth($name, $password))

proc wsOnMessage(e: MessageEvent) =
  let event = unpack($e.data)
  match event:
    Joined(newUser, newRole):
      if not authenticated:
        authenticate(newUser, newRole)
      else:
        showEvent(&"{newUser} joined as {$newRole}")
        server.users.add(newUser)
        if activeTab == usersTab: redraw()
    Left(name):
      showEvent(&"{name} left")
      server.users.keepItIf(it != name)
      if activeTab == usersTab: redraw()
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
      if activeTab == playlistTab: redraw()
    PlaylistPlay(index):
      playIndex(index)
    PlaylistClear:
      showEvent("Cleared playlist")
      server.playlist = @[]
      setState(false, 0.0)
      if activeTab == playlistTab: redraw()
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
    let box = document.getElementById("kinoChat")
    box.scrollTop = box.scrollHeight

proc chatBox(): VNode =
  result = buildHtml(tdiv(class="tabBox", id="kinoChat")):
    for msg in messages:
      let class = if msg.name == "server": "Event" else: "Text"
      tdiv(class=("message" & class)):
        if class == "Text":
          tdiv(class="messageName"): text &"{msg.name}: "
        text msg.text

proc usersBox(): VNode =
  result = buildHtml(tdiv(class="tabBox", id="kinoUsers")):
    if server.users.len > 0:
      for user in server.users:
        tdiv(class="userText"):
          text user & (if user == name: " (You)" else: "")
    else:
      text "No users. (That's weird, you're here tho)"
      
proc playlistBox(): VNode =
  result = buildHtml(tdiv(class="tabBox", id="kinoPlaylist")):
    if server.playlist.len > 0:
      tdiv(class="currentMovieText"):
        text "Now playing: "
        a(href=currentMovie):
          text currentMovie
      for i, movie in server.playlist:
        tdiv(class="movieSource"):
          text &"{i} - "
          a(href=movie): text movie
    else:
      tdiv(class="emptyPlaylistText"):
        text "Nothing is on the playlist yet. Here's some popcorn 🍿!"

proc tabButtons(): VNode =
  result = buildHTml(tdiv(class="tabButtonsGroup")):
    button(class="tabButton", id="btnChat"):
      text "Chat"
      proc onclick() = switchTab(chatTab)
    button(class="tabButton", id="btnUsers"):
      text "Users"
      proc onclick() = switchTab(usersTab)
    button(class="tabButton", id="btnPlaylist"):
      text "Playlist"
      proc onclick() = switchTab(playlistTab)

proc createDom(): VNode =
  result = buildHtml(tdiv):
    tdiv(class="kinopanel"):
      tabButtons()
      chatBox()
      usersBox()
      playlistBox()
      input(id="input", class="messageInput", onkeyupenter=sendMessage)
    tdiv(class="kinobox"):
      video(id="player", playsinline="", controls="", autoplay="")

proc postRender =
  if player == nil:
    player = newPlyr("#player")
    switchTab(chatTab)
  if server.ws == nil:
    wsInit()
  scrollToBottom()

setRenderer createDom, "ROOT", postRender
setForeignNodeId "player"

discard window.setInterval(syncTime, 200)
