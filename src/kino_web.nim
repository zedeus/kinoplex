import std/[strformat, sequtils]
import std/dom except matchMedia
from sugar import `=>`
import websockets, patty
include karax/prelude
import protocol, web/plyr

type
  Server = object
    ws: WebSocket
    host: string
    playlist: seq[string]
    users, jannies: seq[string]
    index: int
    playing: bool
    time: float
    anchor: float  # performance.now() when `time` was valid

  Msg = object
    name, text: kstring

  Tab = enum
    chatTab = "Chat",
    usersTab = "Users",
    playlistTab = "Playlist"

var
  player: Plyr
  server: Server
  name = "guest"
  password = ""
  role = user
  authenticated = false
  messages: seq[Msg]
  activeTab: Tab
  panel: Element
  overlayActive = false
  ovInputActive = false
  overlayBox: Element
  timeout: TimeOut
  rtt = 0.0             # smoothed round-trip time to the server, seconds
  lastSeek = 0.0
  pendingApply = false  # server state not yet applied to the (loading) player
  loadedUrl = ""
  rejoin = false        # connection was lost, log back in automatically

let mediaQuery = window.matchMedia("(max-width: 800px)")

const timeoutVal = 5000

#Forward declarations so we dont run into undefined errors
proc addMessage(m: Msg)
proc showMessage(name, text: string)
proc handleInput()
proc init(p: var Plyr, id: string)
proc wsInit()

proc perfNow(): float {.importjs: "performance.now()".}

proc send(s: Server; data: protocol.Event) =
  if s.ws != nil and s.ws.readyState == ReadyState.Open:
    s.ws.send(cstring($(%data)))

proc getServerUrl(): string =
  let
    protocol = $window.location.protocol
    host = $window.location.host
    path = $window.location.pathname

  if protocol == "https:":
    result = &"wss://{host}"
  else:
    result = &"ws://{host}"

  if path == "/": result &= "/ws"
  else: result &= &"{path}/ws"

proc switchTab(tab: Tab) =
  let
    activeBtn = document.getElementById(cstring("btn" & $tab))
    activeTab = document.getElementById(cstring("kino" & $tab))
  for btn in document.getElementsByClassName("tabButton"):
    btn.class = "tabButton"
  activeBtn.class = "tabButton activeTabButton"
  for tab in document.getElementsByClassName("tabBox"):
    tab.style.display = "none"
  activeTab.style.display = "block"

  if authenticated:
    document.getElementById("input").focus()

proc overlayInput(): VNode =
  buildHtml(tdiv(class="ovInput")):
    label(`for`="ovInput"): text "> "
    input(id="ovInput", maxlength="280")

proc overlayMsg(msg: Msg): VNode =
  buildHtml(tdiv(class="ovMessage")):
    let class = if msg.name == "server": "Event" else: "Text"
    if class == "Text":
      tdiv(class="messageName"): text &"{msg.name}: "
    text msg.text

proc overlayInit() =
  let plyrVideoWrapper = document.getElementsByClassName("plyr__video-wrapper")
  overlayBox = document.createElement("div")
  overlayBox.class = "overlayBox"
  overlayBox.appendChild(document.createElement("div"))
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

proc handleInput() =
  let
    input = document.getElementById(cstring(if overlayActive: "ovInput" else: "input"))
    val = $input.value.strip
  if val.len == 0: return
  input.value = ""
  if not overlayActive and activeTab == playlistTab:
    server.send(PlaylistAdd(val))
  elif not overlayActive and activeTab == usersTab:
    server.send(Renamed($name, val))
  elif val[0] != '/':
    addMessage(Msg(name: kstring(name), text: kstring(val)))
    server.send(Message($name, val))

proc sendPing() =
  if authenticated:
    server.send(Ping(perfNow()))

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
  sendPing()

# Time sync: the server state is an anchor (playing, time at local moment
# `server.anchor`), which is extrapolated with the local clock. The admin
# reports to the server only when its player deviates from that anchor, and
# everyone else follows it, correcting small drift by nudging the playback
# rate instead of seeking.
const
  adminThreshold = 0.5   # seconds the admin may deviate before re-reporting
  seekCooldown = 3000.0  # ms between corrective seeks, so buffering can't loop

proc loaded(): bool = player.duration$float > 0

proc setAnchor(playing: bool; time: float) =
  server.playing = playing
  server.time = time
  server.anchor = perfNow()

proc expectedTime(): float =
  result = server.time
  if server.playing:
    result += (perfNow() - server.anchor) / 1000

proc setRate(rate: float) =
  if player.isHTML5$bool and abs(player.media.playbackRate$float - rate) > 0.001:
    player.media.playbackRate = rate

proc seek(time: float) =
  lastSeek = perfNow()
  player.currentTime = time

proc applyState() =
  ## Make the local player follow the server state
  if not loaded(): return
  pendingApply = false
  let
    target = min(expectedTime(), player.duration$float)
    drift = target - player.currentTime$float
    ended = player.ended$bool

  # don't restart a video that ended slightly before the admin's did
  if server.playing != player.playing$bool and not (server.playing and ended):
    player.togglePlay(server.playing)

  if role == admin or not server.playing:
    setRate(1)
    if abs(drift) > (if role == admin: adminThreshold else: 0.1):
      seek(target)
  elif not ended:
    let seekThreshold = if player.isHTML5$bool: 1.5 else: 1.0
    if abs(drift) > seekThreshold:
      if perfNow() - lastSeek > seekCooldown:
        setRate(1)
        seek(target)
    elif abs(drift) > 0.05:
      # catch up/slow down by at most 5%, imperceptible with preserved pitch
      setRate(1 + clamp(drift * 0.25, -0.05, 0.05))
    elif abs(drift) < 0.015:
      setRate(1)

proc report() =
  ## Admin: tell the server when the player deviates from the shared state
  if role != admin or pendingApply or not loaded(): return
  let
    playing = player.playing$bool
    time = player.currentTime$float
  if playing != server.playing or abs(time - expectedTime()) > adminThreshold:
    setAnchor(playing, time)
    # compensate for the time the message takes to reach the server
    server.send(State(playing, if playing: time + rtt / 2 else: time))

proc onState(playing: bool; time: float) =
  setAnchor(playing, if playing: time + rtt / 2 else: time)
  pendingApply = true
  applyState()

proc onPlayerUpdate() =
  if role == admin and not pendingApply: report()
  else: applyState()

proc loadIndex(index: int) =
  if index notin 0 .. server.playlist.high:
    showEvent(&"Syncing index wrong {index} > {server.playlist.high}")
    return
  server.index = index
  pendingApply = true
  let url = server.playlist[index]
  if url != loadedUrl:
    showEvent("Playing " & url)
    loadedUrl = url
    player.source = url
  if activeTab == playlistTab: redraw()

proc playIndex(index: int) =
  ## Local action, the server answers with the new state
  if role < janny or index notin 0 .. server.playlist.high: return
  server.send(PlaylistPlay(index))
  setAnchor(false, 0)
  loadIndex(index)

proc toggleJanny(user: string, isJanny: bool) =
  if user notin server.users: return
  if role == admin:
    server.send(Janny(user, not isJanny))
  if activeTab == usersTab: redraw()

proc wsOnMessage(e: MessageEvent) =
  let event = unpack($e.data)
  if not authenticated:
    match event:
      Joined(newUser, newRole):
        authenticate(newUser, newRole)
      Error(reason):
        rejoin = false
        window.alert(cstring(reason))
        redraw()
      _: discard
  else:
    match event:
      Joined(newUser, newRole):
        showEvent(&"{newUser} joined as {$newRole}")
        server.users.add(newUser)
        if activeTab == usersTab: redraw()
      Left(name):
        showEvent(&"{name} left")
        server.users.keepItIf(it != name)
        server.jannies.keepItIf(it != name)
        if activeTab == usersTab: redraw()
      Renamed(oldName, newName):
        if oldName == name: name = newName
        let i = server.users.find(oldName)
        if i >= 0: server.users[i] = newName
        if oldName in server.jannies:
          server.jannies[server.jannies.find(oldName)] = newName
        if activeTab == usersTab: redraw()
      Message(name, text):
        showMessage(name, text)
      State(playing, time):
        onState(playing, time)
      PlaylistLoad(urls):
        server.playlist = urls
      PlaylistAdd(url):
        server.playlist.add(url)
        if activeTab == playlistTab: redraw()
      PlaylistPlay(index):
        loadIndex(index)
      PlaylistClear:
        showEvent("Cleared playlist")
        server.playlist = @[]
        server.index = 0
        setAnchor(false, 0)
        applyState()
        loadedUrl = ""
        player.source = ""
        if activeTab == playlistTab: redraw()
      Clients(users):
        server.users = users
        if activeTab == usersTab: redraw()
      Janny(janname, state):
        if role != admin and janname == name:
          role = if state: janny else: user
        if state: server.jannies.add janname
        else: server.jannies.keepItIf(it != janname)
        if activeTab == usersTab: redraw()
      Jannies(jannies):
        server.jannies = jannies
        if activeTab == usersTab: redraw()
      Ping(sentAt):
        let sample = (perfNow() - sentAt) / 1000
        rtt = if rtt == 0: sample else: rtt * 0.8 + sample * 0.2
      Error(reason):
        window.alert(cstring(reason))
      _: discard

proc wsOnOpen(e: dom.Event) =
  if rejoin:
    server.send(Auth(name, password))

proc wsOnClose(e: CloseEvent) =
  if authenticated:
    rejoin = true
    showEvent("Connection lost, reconnecting...")
  authenticated = false
  role = user
  server.users = @[]
  server.jannies = @[]
  server.playlist = @[]
  redraw()
  discard setTimeout(wsInit, 2000)

proc wsInit() =
  server.ws = newWebSocket(cstring(server.host))
  server.ws.onOpen = wsOnOpen
  server.ws.onClose = wsOnClose
  server.ws.onMessage = wsOnMessage

proc scrollToBottom() =
  if activeTab == chatTab:
    let box = document.getElementById("kinoChat")
    box.scrollTop = box.scrollHeight

proc parseAction(ev: dom.Event, n: VNode) =
  case $n.id
  of "playMovie": playIndex(n.index)
  of "clearPlaylist": server.send(PlaylistClear())
  of "toggleJanny":
    let user = server.users[n.index]
    toggleJanny(user, user in server.jannies)
  # More to come
  else: discard

proc chatBox(): VNode =
  buildHtml(tdiv(class="tabBox", id="kinoChat")):
    for msg in messages:
      let class = if msg.name == "server": "Event" else: "Text"
      tdiv(class=kstring("message" & class)):
        if class == "Text":
          tdiv(class="messageName"): text &"{msg.name}: "
        text msg.text

proc usersBox(): VNode =
  buildHtml(tdiv(class="tabBox", id="kinoUsers")):
    if server.users.len > 0:
      for i, user in server.users:
        tdiv(class="userElem"):
          text user
          if user == name: text " (You)"
          elif role == admin:
            button(id="toggleJanny", class="actionBtn", index = i, onclick=parseAction):
              text "Tog. Janny"
          if user in server.jannies: text " (Janny)"
    else:
      text "No users. (That's weird, you're here tho)"

proc playlistBox(): VNode =
  buildHtml(tdiv(class="tabBox", id="kinoPlaylist")):
    if server.playlist.len > 0:
      for i, movie in server.playlist:
        tdiv(class="movieElem"):
          span(class="movieSource"):
            a(href=kstring(movie)): text kstring($movie.split("://")[1])
          if role > user:
            if server.index != i:
              button(id="playMovie", index=i, class="actionBtn", onclick=parseAction):
                text "▶"
    else:
      tdiv(class="emptyPlaylistText"):
        text "Nothing is on the playlist yet. Here's some popcorn 🍿!"

proc tabButtons(): VNode =
  buildHTml(tdiv(class="tabButtonsGroup")):
    button(class="tabButton", id="btnChat"):
      text "Chat"
      proc onclick() = activeTab = chatTab
    button(class="tabButton", id="btnUsers"):
      text "Users"
      proc onclick() = activeTab = usersTab
    button(class="tabButton", id="btnPlaylist"):
      text "Playlist"
      proc onclick() = activeTab = playlistTab


proc resizeCallback(ev: dom.Event) =
  template px(size: untyped): cstring =
    cstring($size & "px")

  ev.preventDefault()
  if mediaQuery.matches$bool:
    panel.style.height = px(window.innerHeight - ((MouseEvent)ev).pageY)
  else:
    panel.style.width = px(((MouseEvent)ev).pageX)

# Converted to closures once, so add/removeEventListener get the same function object
let resizeCb: proc (ev: dom.Event) = resizeCallback

proc stopResize(ev: dom.Event) =
  document.removeEventListener("mousemove", resizeCb)
  document.body.style.cursor = "unset"

let stopResizeCb: proc (ev: dom.Event) = stopResize

proc resizeHandle(): VNode =
  result = buildHtml(tdiv(id="resizeHandle")):
    proc onmousedown() =
      if panel == nil:
        panel = document.getElementById("kinopanel")

      document.body.style.cursor = if mediaQuery.matches$bool: "ns-resize"
                                   else: "ew-resize"

      document.addEventListener("mousemove", resizeCb)
      document.addEventListener("mouseup", stopResizeCb)

proc onkeypress(ev: dom.Event) =
  let ke = (KeyboardEvent)ev
  if player.fullscreen.active$bool:
    if ke.keyCode == 13:
      ev.preventDefault()
      ovInputActive = not ovInputActive
      if not ovInputActive:
        let ovInput = document.getElementById("ovInput")
        if ovInput.value.len > 0:
          handleInput()
          return

    redrawOverlay()

proc init(p: var Plyr, id: string) =
  p = newPlyr(id)
  p.muted = true

  p.on("ready", overlayInit)
  p.on("enterfullscreen", redrawOverlay)
  p.on("exitfullscreen", () => (if overlayActive:
                                  ovInputActive = false
                                  clearOverlay()))
  for ev in [cstring"loadedmetadata", "durationchange", "canplay", "timeupdate",
             "playing", "pause", "seeked"]:
    p.on(ev, onPlayerUpdate)
  p.on("ended", () => (if role == admin and server.index < server.playlist.high:
                         playIndex(server.index + 1)))

  document.addEventListener("keypress", onkeypress)

proc loginAction() =
  name = $getVNodeById("user").getInputText
  password = $getVNodeById("password").getInputText

  server.send(Auth(name, password))

proc loginOverlay(): VNode = 
  buildHtml(tdiv(id="loginOverlay")):
    tdiv(id="loginForm"):
      label:
        text "ｋｉｎｏｐｌｅｘ"

      input(id="user", placeholder="Username", onkeyupenter=loginAction)
      input(id="password", placeholder="Password (admin only)", onkeyupenter=loginAction)
      button(id="submit", class="actionBtn", onclick=loginAction):
        text "Join"

proc createDom(): VNode =
  buildHtml(tdiv):
    if not authenticated and not rejoin: loginOverlay()

    tdiv(id="kinopanel"):
      tabButtons()
      chatBox()
      usersBox()
      playlistBox()
      if activeTab == playlistTab and role == admin:
        button(id="clearPlaylist", class = "actionBtn", onclick=parseAction):
          text "Clear Playlist"

      if activeTab == playlistTab and role < janny:
        input(id="input", class="messageInput", disabled="", placeholder="Only jannies can add links")
      else:
        input(id="input", class="messageInput", onkeyupenter=handleInput, maxlength="280")
    resizeHandle()
    tdiv(id="kinobox"):
      video(id="player", playsinline="", controls="")

proc postRender =
  if not authenticated and not rejoin:
    document.getElementById("user").focus()

  if player == nil:
    player.init("#player")
  
  switchTab(activeTab)
  scrollToBottom()

server = Server(host: getServerUrl())
wsInit()
discard setInterval(sendPing, 5000)

setRenderer createDom, "ROOT", postRender
setForeignNodeId "player"

mediaQuery.addListener((e: JsObject) =>
  (if panel != nil:
     if e.matches$bool:
       if not panel.style.width.isNil:
         panel.style.width = nil
         panel.style.height = "360px"
     elif not panel.style.height.isNil:
       panel.style.width = "340px"
       panel.style.height = nil))
