import std/[dom, strformat, sequtils, uri]
from sugar import `=>`
import patty
include karax / prelude
import lib/[protocol, kino_client]
import web/plyr

type
  WebClient = ref object of Client
    authenticated: bool
    password: string

  Tab = enum
    chatTab = "Chat",
    usersTab = "Users",
    playlistTab = "Playlist"

var
  player: Plyr
  client: WebClient
  server: Server
  activeTab: Tab
  panel: Element
  overlayActive = false
  ovInputActive = false
  overlayBox: Element
  timeout: TimeOut

let mediaQuery = window.matchMedia("(max-width: 800px)")

const timeoutVal = 5000

#Forward declarations so we dont run into undefined errors
proc addMessage(m: Msg)
proc showMessage(name, text: string)
proc handleInput()
proc init(p: var Plyr, id: string)

proc getServerUrl(): string =
  let
    protocol = window.location.protocol
    host = $window.location.host
    path = $window.location.pathname

  result = getServerUri("s" in protocol, host, path)

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

  if client.authenticated:
    document.getElementById("input").focus()

proc overlayInput(): VNode =
  buildHtml(tdiv(class="ovInput")):
    label(`for`="ovInput"): text "> "
    input(id="ovInput", onkeyupenter=handleInput, maxlength="280")

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
  for msg in server.recentMsgs(5):
    overlayBox.firstChild.appendChild vnodeToDom(overlayMsg(msg))

  if not ovInputActive: timeout = setTimeout(clearOverlay, timeoutVal)
  elif overlayBox.lastChild.class != "ovInput":
    overlayBox.appendChild vnodeToDom(overlayInput())
    overlayBox.lastChild.lastChild.focus()

  overlayActive = true

proc addMessage(m: Msg) =
  server.messages.add(m)
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
    client.send(PlaylistAdd(val))
  elif not overlayActive and activeTab == usersTab:
    client.send(Renamed(client.name, val))
  elif val[0] != '/':
    addMessage(Msg(name: client.name, text: val))
    client.send(Message(client.name, val))

proc syncTime() =
  if player.duration$float == 0: return

  let
    currentTime = player.currentTime$float
    diff = abs(currentTime - server.time)
  if client.role == admin:
    if diff >= 0.2:
      server.time = currentTime
      client.send(State(player.playing$bool and player.loaded, server.time))
  elif diff > 1:
    player.currentTime = server.time

proc syncPlaying() =
  if client.role == admin:
    server.playing = player.playing$bool
    client.send(State(server.playing and player.loaded, server.time))
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
    if client.role == admin:
      client.send(PlaylistPlay(index))
      client.send(State(false, 0))
  showEvent("Playing " & server.playlist[index])
  server.index = index
  player.source = server.playlist[index]
  if activeTab == playlistTab: redraw()

proc toggleJanny(user: string, isJanny: bool) =
  if user notin server.users: return
  if client.role == admin:
    client.send(Janny(user, not isJanny))
  if activeTab == usersTab: redraw()

proc handleServer() =
  client.poll(event):
    match event:
      Joined(newUser, newRole):
        showEvent(&"{newUser} joined as {$newRole}")
        server.users.add(newUser)
        if client.role == admin:
          syncTime()
        if activeTab == usersTab: redraw()
      Left(name):
        showEvent(&"{name} left")
        server.users.keepItIf(it != name)
        server.jannies.keepItIf(it != name)
        if activeTab == usersTab: redraw()
      Renamed(oldName, newName):
        if oldName == client.name: client.name = newName
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
      Janny(name, isJanny):
        if client.role != admin:
          client.role = if isJanny and client.name == name: janny else: user
        if isJanny: server.jannies.add name
        else: server.jannies.keepItIf(it != name)
        if activeTab == usersTab: redraw()
      Jannies(jannies):
        server.jannies = jannies
        if activeTab == usersTab: redraw()
      Error(reason):
        window.alert(cstring(reason))
      _: discard

proc wsOnClose(e: CloseEvent) =
  close client.ws
  showEvent("Connection closed")

proc scrollToBottom() =
  if activeTab == chatTab:
    let box = document.getElementById("kinoChat")
    box.scrollTop = box.scrollHeight

proc parseAction(ev: dom.Event, n: VNode) =
  case $n.id
  of "playMovie": syncIndex(n.index)
  of "clearPlaylist": client.send(PlaylistClear())
  of "toggleJanny":
    let user = server.users[n.index]
    toggleJanny(user, user in server.jannies)
  # More to come
  else: discard

proc chatBox(): VNode =
  buildHtml(tdiv(class="tabBox", id="kinoChat")):
    for msg in server.messages:
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
          if user == client.name: text " (You)"
          elif client.role == admin:
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
            let kmovie = kstring(movie)
            a(href=kmovie): text kmovie.split("://")[1]
          if client.role > user:
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

proc resizeHandle(): VNode =
  result = buildHtml(tdiv(id="resizeHandle")):
    proc onmousedown() =
      if panel == nil:
        panel = document.getElementById("kinopanel")

      document.body.style.cursor = if mediaQuery.matches$bool: cstring"ns-resize"
                                   else: cstring"ew-resize"

      document.addEventListener("mousemove", resizeCallback)
      document.addEventListener("mouseup",
        (ev: dom.Event) => (document.removeEventListener("mousemove", resizeCallback);
                            document.body.style.cursor = "unset"))

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
  p.muted = true

  p.on("ready", overlayInit)
  p.on("enterfullscreen", redrawOverlay)
  p.on("exitfullscreen", () => (if overlayActive:
                                  ovInputActive = false
                                  clearOverlay()))
  p.on("timeupdate", syncTime)
  p.on("playing", syncPlaying)
  p.on("pause", syncPlaying)
  p.on("ended", () => (if client.role == admin:
                         if server.index < server.playlist.high:
                           syncIndex(server.index + 1)
                         else:
                           setState(false, player.currentTime$float)))

  document.addEventListener("keypress", onkeypress)

proc loginAction() =
  client.name = $getVNodeById("user").getInputText
  client.password = $getVNodeById("password").getInputText

  client.authenticate(client.password, resp):
    match resp:
      Joined(newUser, newRole):
        client.name = newUser
        if newRole != user:
          client.role = newRole
          showEvent(&"Welcome to the kinoplex, {newRole}!")
        else:
          showEvent("Welcome to the kinoplex!")
          if client.password.len > 0 and newRole == user:
            showEvent("Admin authentication failed")
        client.authenticated = true
      Error(reason):
        window.alert(cstring(reason))
      _: discard

    if client.authenticated: handleServer()

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
    if not client.authenticated: loginOverlay()

    tdiv(id="kinopanel"):
      tabButtons()
      chatBox()
      usersBox()
      playlistBox()
      if activeTab == playlistTab and client.role == admin:
        button(id="clearPlaylist", class = "actionBtn", onclick=parseAction):
          text "Clear Playlist"

      if activeTab == playlistTab and client.role < janny:
        input(id="input", class="messageInput", disabled="", placeholder="Only jannies can add links")
      else:
        input(id="input", class="messageInput", onkeyupenter=handleInput, maxlength="280")
    resizeHandle()
    tdiv(id="kinobox"):
      video(id="player", playsinline="", controls="")

proc postRender =
  if not client.authenticated:
    document.getElementById("user").focus()

  if player == nil:
    player.init("#player")
  
  switchTab(activeTab)
  scrollToBottom()

server = Server(host: getServerUrl())

client = WebClient(ws: newWebSocket(cstring(server.host)))
client.ws.onClose = wsOnClose

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
