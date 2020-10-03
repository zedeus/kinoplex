import jswebsockets, protocol, patty, plyr, dom, strformat, sequtils
from sugar import `=>`
include karax / prelude

type
  Server = object
    ws: WebSocket
    host: string
    playlist: seq[string]
    users, jannies: seq[string]
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
  server = Server(host: "ws://localhost:9001/ws")
  name = window.prompt("Enter username: ", "guest")
  password = window.prompt("Enter password (or leave empty):", "")
  role = user
  loading = false
  reloading = false
  authenticated = false
  messages: seq[Msg]
  activeTab: Tab
  panel: Node
  overlayActive = false
  ovInputActive = false
  overlayBox: Node
  timeout: TimeOut

const timeoutVal = 5000

#Forward declarations so we dont run into undefined errors
proc addMessage(m: Msg)
proc showMessage(name, text: string)
proc handleInput()

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
  document.getElementById("input").focus()

proc overlayInput(): VNode =
  result = buildHtml(tdiv(class="ovInput")):
    label(`for`="ovInput"): text "> "
    input(id="ovInput", onkeyupenter=handleInput, maxlength="280")

proc overlayMsg(msg: Msg): VNode =
  result = buildHtml(tdiv(class="ovMessage")):
    let class = if msg.name == "server": "Event" else: "Text"
    if class == "Text":
      tdiv(class="messageName"): text &"{msg.name}: "
    text msg.text

proc overlayInit() =
  let plyrVideoWrapper = document.getElementsByClassName("plyr__video-wrapper")
  overlayBox = document.createElement("div")
  overlayBox.class = "overlayBox"
  overlayBox.appendChild document.createElement("div")
  overlayBox.firstChild.class = "overlayMessages"
  if plyrVideoWrapper.len > 0:
    plyrVideoWrapper[0].appendChild(overlayBox)

proc clearOverlay() =
  let overlayMessages = overlayBox.firstChild
  while(overlayMessages.lastChild != nil):
    overlayMessages.removeChild(overlayMessages.lastChild)

  if overlayBox.lastChild.class == "ovInput" and not ovInputActive:
    overlayBox.removeChild(overlayBox.lastChild)
      
  overlayActive = false

proc redrawOverlay() =
  if timeout != nil: clearTimeout(timeout)
  if overlayActive: clearOverlay()
  for msg in messages[max(0, messages.len-5) .. ^1]:
    overlayBox.firstChild.appendChild vnodeToDom(overlayMsg(msg))

  if not ovInputActive: timeout = setTimeout(clearOverlay, timeoutVal)
  elif overlayBox.lastChild.class != "ovInput":
    overlayBox.appendChild vnodeToDom(overlayInput())
    overlayBox.lastChild.lastChild.focus()

  overlayActive = true

proc addMessage(m: Msg) =
  messages.add(m)
  if player.fullscreen.active$bool: redrawOverlay()
  if activeTab == chatTab: redraw()

proc showMessage(name, text: string) =
  addMessage(Msg(name: name, text: text))

proc showEvent(text: string) =
  addMessage(Msg(name: "server", text: text))
  echo text

proc handleInput() =
  let
    input = document.getElementById(if overlayActive: "ovInput" else: "input")
    val = $input.value.strip
  if val.len == 0: return
  input.value = ""
  if not overlayActive and activeTab == playlistTab:
    server.send(PlaylistAdd(val))
  elif not overlayActive and activeTab == usersTab:
    server.send(Renamed($name, val))
  elif val[0] != '/':
    addMessage(Msg(name: name, text: val))
    server.send(Message($name, val))

proc authenticate(newUser: string; newRole: Role) =
  name = newUser
  if newRole != user:
    role = newRole
    showEvent(&"Welcome to the kinoplex, {role}!")
  else:
    showEvent("Welcome to the kinoplex!")
    if password.len > 0 and newRole == user:
      showEvent("Admin authentication failed")
  authenticated = true

proc syncTime() =
  if player.duration$float == 0: return
  let
    currentTime = player.currentTime$float
    diff = abs(currentTime - server.time)
  if role == admin:
    if diff >= 0.2:
      server.time = currentTime
      server.send(State(player.playing$bool and player.loaded, server.time))
  elif diff > 1:
    player.currentTime = server.time

proc syncPlaying() =
  if role == admin:
    server.playing = player.playing$bool
    server.send(State(server.playing and player.loaded, server.time))
  else:
    if server.playing != player.playing$bool:
      player.togglePlay(server.playing)
    if player.paused$bool and player.currentTime$float != server.time:
      player.currentTime = server.time

proc setState(playing: bool; time: float) =
  server.time = time
  syncTime()
  server.playing = playing
  syncPlaying()

proc syncIndex(index: int) =
  if index == -1: return
  if index != server.index and server.playlist.len > 0:
    if index > server.playlist.high:
      showEvent(&"Syncing index wrong {index} > {server.playlist.high}")
      return
    if role == admin:
      server.send(PlaylistPlay(index))
      server.send(State(false, 0))
  showEvent("Playing " & server.playlist[index])
  server.index = index
  player.source = server.playlist[index]
  if activeTab == playlistTab: redraw()

proc toggleJanny(user: string, isJanny: bool) =
  if user notin server.users: return
  if role == admin:
    server.send(Janny(user, not isJanny))
  if activeTab == usersTab: redraw()

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
        # Force a resync if the movie is paused
        if role == admin and not player.playing$bool:
          syncTime()
          syncPlaying()
        if activeTab == usersTab: redraw()
    Left(name):
      showEvent(&"{name} left")
      server.users.keepItIf(it != name)
      server.jannies.keepItIf(it != name)
      if activeTab == usersTab: redraw()
    Renamed(oldName, newName):
      if oldName == name: name = newName
      server.users[server.users.find(oldName)] = newName
      if oldName in server.jannies:
        server.jannies[server.jannies.find(oldName)] = newName
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
        syncIndex(0)
      if activeTab == playlistTab: redraw()
    PlaylistPlay(index):
      syncIndex(index)
    PlaylistClear:
      showEvent("Cleared playlist")
      server.playlist = @[]
      setState(false, 0.0)
      player.source = ""
      if activeTab == playlistTab: redraw()
    Clients(users):
      server.users = users
      if activeTab == usersTab: redraw()
    Janny(janname, state):
      if role != admin:
        role = if state and name == janname: janny else: user
      if state: server.jannies.add janname
      else: server.jannies.keepItIf(it != janname)
      if activeTab == usersTab: redraw()
    Jannies(jannies):
      server.jannies = jannies
      if activeTab == usersTab: redraw()
    Error(reason):
      window.alert(reason)
    _: discard

proc wsOnClose(e: CloseEvent) =
  close server.ws
  showEvent("Connection closed")

proc wsInit() =
  server.ws = newWebSocket(server.host)
  server.ws.onOpen = wsOnOpen
  server.ws.onClose = wsOnClose
  server.ws.onMessage = wsOnMessage

proc scrollToBottom() =
  if activeTab == chatTab:
    let box = document.getElementById("kinoChat")
    box.scrollTop = box.scrollHeight

proc parseAction(ev: dom.Event, n: VNode) =
  case $n.id
  of "playMovie": syncIndex(n.index)
  of "clearPlaylist": server.send(PlaylistClear())
  of "toggleJanny":
    let user = server.users[n.index]
    toggleJanny(user, user in server.jannies)
  # More to come
  else: discard

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
      for i, user in server.users:
        let class = 
          if user in server.jannies: 
            "userElemMod" else: "userElem"

        tdiv(class=class):
          text user
          if user == name: 
            tdiv(class="userElemSelf"): text "(You)"
          elif role == admin:
            button(id="toggleJanny", class="actionBtn", index = i, onclick=parseAction):
              text "Tog. Janny"
    else:
      text "No users. (That's weird, you're here tho)"

proc playlistBox(): VNode =
  result = buildHtml(tdiv(class="tabBox", id="kinoPlaylist")):
    if server.playlist.len > 0:
      for i, movie in server.playlist:
        tdiv(class="movieElem"):
          span(class="movieSource"):
            a(href=movie): text movie.split("://")[1]
          if role == admin:
            if server.index != i:
              button(id="playMovie", index=i, class="actionBtn", onclick=parseAction):
                text "▶"
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
  var isResizing = false

  result = buildHtml(tdiv(class="resizeHandle")):
    proc onmousedown() =
      isResizing = true
    proc onmouseup() =
      isResizing = false

  document.addEventListener("mousemove", (ev: dom.Event) =>
   (if isResizing: panel.style.width = $((MouseEvent)ev).clientX))

proc onkeypress(ev: dom.Event) =
  let ke = (KeyboardEvent)ev
  if player.fullscreen.active$bool:
    if ke.keyCode == 13:
      ev.preventDefault()
      ovInputActive = not ovInputActive
      if not ovInputActive:
        let ovInput = document.getElementById("ovInput")
        if ovInput.value.len > 0: return
    redrawOverlay()

proc init(p: var Plyr, id: string) =
  p = newPlyr(id)
  p.on("ready", overlayInit)
  p.on("enterfullscreen", redrawOverlay)
  p.on("exitfullscreen", () => (if overlayActive:
                                  ovInputActive = false
                                  clearOverlay()))
  p.on("timeupdate", syncTime)
  p.on("playing", syncPlaying)
  p.on("pause", syncPlaying)
  document.addEventListener("keypress", onkeypress)

proc createDom(): VNode =
  result = buildHtml(tdiv):
    tdiv(class="kinopanel"):
      tabButtons()
      chatBox()
      usersBox()
      playlistBox()
      if activeTab == playlistTab and role == admin:
        button(id="clearPlaylist", class = "actionBtn", onclick=parseAction):
          text "Clear Playlist"
      input(id="input", class="messageInput", onkeyupenter=handleInput, maxlength="280")
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