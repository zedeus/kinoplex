import jswebsockets, protocol, patty, plyr, dom, strformat, sequtils
from sugar import `=>`
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
    chatTab = "Chat",
    usersTab = "Users",
    playlistTab = "Playlist"

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
  currentIndex: int
  panel: Node
  overlayActive = false
  ovInputActive = false
  overlayBox: Node
  timeout: TimeOut

const timeoutVal = 5000

#Forward declarations so we dont run into undefined errors
proc addMessage(m: Msg)
proc showMessage(name, text: string)
proc sendMessage()

proc send(s: Server; data: protocol.Event) =
  server.ws.send($(%data))

proc switchTab(tab: Tab) =
  activeTab = tab
  let
    activeBtn = document.getElementById("btn" & $tab)
    activeTab = document.getElementById("kino" & $tab)
  for btn in document.getElementsByClassName("tabButton"):
    btn.class = "tabButton"
  activeBtn.class = "tabButton activeTabButton"
  for tab in document.getElementsByClassName("tabBox"):
    tab.style.display = "none"
  activeTab.style.display = "block"

proc overlayInput(): VNode =
  result = buildHtml(tdiv(class="ovInput")):
    label(`for`="ovInput"): text "> "
    input(id="ovInput", onkeyupenter=sendMessage, setFocus=true)

proc overlayMsg(msg: Msg): VNode =
  result = buildHtml(tdiv(class="overlayMsg")):
    let class = if msg.name == "server": "Event" else: "Text"
    if class == "Text":
      tdiv(class="messageName"): text &"{msg.name}: "
    text msg.text

proc clearOverlay() =
  while(overlayBox.lastChild != nil):
    overlayBox.removeChild(overlayBox.lastChild)

  overlayActive = false

proc redrawOverlay() =
  if overlayBox != nil:
    if timeout != nil: clearTimeout(timeout)
    if overlayActive: clearOverlay()
    for msg in messages[max(0, messages.len-5) .. ^1]:
      let messageElem = vnodeToDom(overlayMsg(msg))
      overlayBox.appendChild(messageElem)
    if ovInputActive:
      overlayBox.appendChild(vnodeToDom(overlayInput()))
      document.getElementById("ovInput").focus()
    else:
      timeout = setTimeout(clearOverlay, timeoutVal)

    overlayActive = true

proc addMessage(m: Msg) =
  messages.add(m)
  if player.fullscreen.active.to bool: redrawOverlay()
  if activeTab == chatTab: redraw()

proc showMessage(name, text: string) =
  addMessage(Msg(name: name, text: text))

proc showEvent(text: string) =
  addMessage(Msg(name: "server", text: text))
  echo text

proc sendMessage() =
  let
    input = document.getElementById(if overlayActive: "ovInput" else: "input")
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

proc syncTime() =
  let
    currentTime = player.currentTime.to float
    diff = abs(currentTime - server.time)
  if role != admin:
    if diff > 1 and diff != 0:
      player.currentTime = server.time

proc playIndex(index: int) =
  showEvent("Playing " & server.playlist[index])
  player.source = server.playlist[index]
  currentIndex = index
  if activeTab == playlistTab: redraw()

proc setState(playing: bool; time: float) =
  server.time = time
  syncTime()
  server.playing = playing
  player.togglePlay(playing)

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
      for i, movie in server.playlist:
        tdiv(class="movieSource", style.backgroundColor = if currentIndex == i: "#282828" else: "#222222"):
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


proc resizeHandle(): VNode =
  result = buildHtml(tdiv(class="resizeHandle")):
    var isDragging = false
    proc onmousedown() =
      isDragging = true
    proc onmouseup() =
      isDragging = false
    proc onmouseout(ev: dom.Event; n: VNode) =
      if panel != nil and isDragging:
        let me = (MouseEvent)ev
        panel.style.width = $me.clientX

proc onkeypress(ev: dom.Event) =
  let ke = (KeyboardEvent)ev
  var forceRedraw = true
  if player.fullscreen.active.to bool:
    if ke.keyCode == 13:
      ovInputActive = not ovInputActive
      if not ovInputActive:
        let ovInput = document.getElementById("ovInput")
        if ovInput.value.len > 0: forceRedraw = false # Because it would break sendMessage otherwise
      if forceRedraw: redrawOverlay()

proc init(p: var Plyr, id: string) =
  p = newPlyr(id)
  p.on("ready", () => debugEcho "Loaded plyr")
  p.on("enterfullscreen", redrawOverlay)
  p.on("exitfullscreen", () => (if overlayActive: clearOverlay()))

  let plyrVideoWrapper = document.getElementsByClassName("plyr__video-wrapper")
  overlayBox = document.createElement("div")
  overlayBox.class = "overlayBox"
  document.addEventListener("keypress", onkeypress)
  if plyrVideoWrapper.len > 0:
    plyrVideoWrapper[0].appendChild(overlayBox)

proc createDom(): VNode =
  result = buildHtml(tdiv):
    tdiv(class="kinopanel"):
      tabButtons()
      chatBox()
      usersBox()
      playlistBox()
      input(id="input", class="messageInput", onkeyupenter=sendMessage)
    resizeHandle()
    tdiv(class="kinobox"):
      video(id="player", playsinline="", controls="", autoplay="")

proc postRender =
  if player == nil:
    player.init("#player")
    switchTab(chatTab)
  if server.ws == nil:
    wsInit()
  if panel == nil:
    panel = document.getElementsByClassName("kinopanel")[0]
  scrollToBottom()

setRenderer createDom, "ROOT", postRender
setForeignNodeId "player"

discard window.setInterval(syncTime, 200)
