import std/[os, asyncdispatch, json, strformat, strutils]
import ws
import lib/[protocol, client, utils]
import mpv/[mpv, config]

type
  Server = object
    host: string
    playlist: seq[string]
    index: int
    playing: bool
    time: float

  MpvClient = ref object of Client

let
  cfg = getConfig()

var
  mpvClient = MpvClient(name: cfg.username)
  server: Server
  player: Mpv
  messages: seq[string]
  loading = false
  reloading = false

proc killKinoplex() =
  echo "Leaving"
  close player
  close mpvClient.ws

template sendEvent(client: MpvClient, event: Event): untyped =
  asyncCheck client.send(event)

proc showText(text: string) =
  player.showText(text)
  stdout.write(text, "\n")
  messages.add text

proc showEvent(text: string) =
  player.showEvent(text)
  stdout.write(text, "\n")

proc showChatLog(count=6) =
  player.clearChat()
  for m in messages[max(messages.len - count, 0) .. ^1]:
    player.showText(m)

proc join(): Future[bool] {.async.} =
  var error: bool
  
  echo "Joining.."
  mpvCLient.authenticate(cfg.password, resp):
    match resp:
      Joined(newName, newRole):
        mpvClient.name = newName
        if newRole != user:
          mpvClient.role = newRole
          showEvent(&"Welcome to the kinoplex, {mpvClient.role}!")
        else:
          showEvent("Welcome to the kinoplex!")
        if cfg.password.len > 0 and newRole == user:
          showEvent("Admin authentication failed")
      Error(reason):
        showEvent("Join failed: " & reason)
        error = true
      _: discard

  return error

proc clearPlaylist() =
  player.playlistClear()
  loading = false

proc setState(playing: bool; time: float; index=(-1)) =
  if index > -1:
    server.index = index
  server.playing = playing
  server.time = time
  player.setPlaying(playing)
  player.setTime(time)

proc updateIndex() {.async.} =
  while loading:
    await sleepAsync(150)

  if server.playlist.len == 0:
    return
  if server.index > server.playlist.high:
    showEvent("Loading went wrong")
    return
  player.playlistPlay(server.index)
  showEvent("Playing " & server.playlist[server.index])

proc syncPlaying(playing: bool) =
  if mpvClient.role == admin:
    player.playing = playing
    server.playing = playing
    mpvClient.sendEvent(State(not loading and player.playing, server.time))
  else:
    if server.playing != playing:
      player.setPlaying(server.playing)

proc syncTime(time: float) =
  player.time = time
  if mpvClient.role == admin:
    server.time = player.time
    mpvClient.sendEvent(State(not loading and player.playing, server.time))
  else:
    let diff = player.time - server.time
    if diff > 1:
      showEvent("Syncing time")
      player.setTime(server.time)

proc syncIndex(index: int) =
  if index == -1: return
  if mpvClient.role == admin and index != server.index:
    if index > server.playlist.high:
      showEvent(&"Syncing index wrong {index} > {server.playlist.high}")
      return
    showEvent("Playing " & server.playlist[index])
    mpvClient.sendEvent(PlaylistPlay(index))
    mpvClient.sendEvent(State(false, 0))
    setState(false, 0, index=index)
  else:
    if index != server.index and server.playlist.len > 0:
      setState(server.playing, server.time, index=server.index)
      if not loading:
        asyncCheck updateIndex()

proc reloadPlayer() =
  reloading = true
  if mpvClient.role == admin:
    mpvClient.sendEvent(State(false, player.time))
  clearPlaylist()
  for url in server.playlist:
    player.playlistAppend(url)
  setState(server.playing, server.time)
  asyncCheck updateIndex()
  showChatLog()

proc updateTime() {.async.} =
  while player.running:
    if not loading:
      player.getTime()
    await sleepAsync(500)

proc handleMessage(msg: string) {.async.} =
  if msg.len == 0: return
  if msg[0] != '/':
    mpvClient.sendEvent(Message(mpvClient.name, msg[0..min(280, msg.high)]))
    showText(&"{mpvClient.name}: {msg}")
    return

  let parts = msg.split(" ", maxSplit=1)
  case parts[0].strip(chars={'/'})
  of "i", "index":
    if parts.len == 1:
      showEvent("No index given")
    elif mpvClient.role != admin:
      showEvent("You don't have permission")
    else:
      syncIndex(parseInt(parts[1]))
  of "a", "add":
    if parts.len == 1 or not validUrl(parts[1]):
      showEvent("No url specified")
    else:
      mpvClient.sendEvent(PlaylistAdd(parts[1]))
  of "o", "open":
    if parts.len == 1 or not validUrl(parts[1], acceptFile=true):
      showEvent("No file or url specified")
    elif "http" notin parts[1] and not fileExists(parts[1]):
      showEvent("File doesn't exist")
    elif server.playlist.len == 0:
      showEvent("Playlist is empty")
    else:
      reloading = true
      loading = true
      if mpvClient.role == admin:
        mpvClient.sendEvent(State(false, player.time))
      player.playlistAppend(parts[1])
      player.playlistMove(server.playlist.len, player.index)
      asyncCheck player.playlistPlayAndRemove(player.index, player.index + 1)
  of "c", "clear":
    player.clearChat()
  of "l", "log":
    let count = if parts.len > 1: parseInt parts[1] else: 6
    showChatLog(count)
  of "u", "users":
    mpvClient.sendEvent(Clients(@[]))
  of "j", "janny":
    if parts.len == 1:
      showEvent("No user specified")
    else:
      mpvClient.sendEvent(Janny(parts[1], true))
  of "unjanny":
    if parts.len == 1:
      showEvent("No user specified")
    else:
      mpvClient.sendEvent(Janny(parts[1], false))
  of "js", "jannies":
    mpvClient.sendEvent(Jannies(@[]))
  of "h":
    player.showText("help yourself")
  of "r", "reload":
    reloadPlayer()
  of "e", "empty":
    mpvClient.sendEvent(PlaylistClear())
  of "n", "rename":
    if parts.len == 1:
      showEvent("No name specified")
    else:
      mpvClient.sendEvent(Renamed(mpvClient.name, parts[1]))
  of "restart":
    if mpvClient.role == admin:
      mpvClient.sendEvent(State(false, player.time))
    await player.restart(cfg.binPath)
    reloadPlayer()
  of "quit":
    killKinoplex()
  else: discard

proc handleMpv() {.async.} =
  while player.running:
    let msg = try: await player.recvLine()
              except: ""

    if msg.len == 0:
      if not player.running:
        break
      if mpvClient.role == admin:
        mpvClient.sendEvent(State(false, player.time))
      await player.restart(cfg.binPath)
      reloadPlayer()
      continue

    let resp = parseJson(msg)
    case resp{"request_id"}.getInt(0)
    of 1: # seek
      if not reloading and resp.hasKey("data"):
        syncTime(resp["data"].getFloat)
        continue
    else: discard

    let event = resp{"event"}.getStr
    case event
    of "pause", "unpause":
      let playing = event == "unpause"
      if not loading:
        syncPlaying(playing)
      player.playing = playing
    of "property-change":
      if resp{"name"}.getStr == "playlist-pos":
        player.index = resp{"data"}.getInt(-1)
        if not reloading:
          syncIndex(player.index)
    of "seek":
      player.getTime()
      loading = true
    of "start-file":
      loading = true
    of "playback-restart":
      loading = false
      reloading = false
      if server.time != 0:
        player.setTime(server.time)
      if server.time == player.time:
        syncPlaying(player.playing)
      syncIndex(player.index)
    of "client-message":
      let args = resp{"args"}.getElems()
      if args.len == 0: continue
      case args[0].getStr()
      of "msg":
        await handleMessage(args[1].getStr)
      of "add":
        for url in args[1].getStr.split("\n"):
          if validUrl(url):
            mpvClient.sendEvent(PlaylistAdd(url))
      of "quit":
        killKinoplex()
      of "scrollback":
        showChatLog()
      else: discard
    of "idle":
      # either failed to load or reset
      loading = false
    else: discard

proc handleServer() {.async.} =
  if await join(): return
  mpvClient.ws.setupPings(5)
  mpvClient.poll(event):
    match event:
      Message(name, text):
        if name == "server":
          showEvent(text)
        else:
          showText(&"{name}: {text}")
      State(playing, time):
        setState(playing, time)
      Clients(names):
        showEvent("Users: " & names.join(", "))
      Joined(name, role):
        showEvent(&"{name} joined as {role}")
      Left(name):
        showEvent(name & " left")
      Renamed(oldName, newName):
        if oldName == mpvClient.name: mpvClient.name = newName
      Janny(jannyName, isJanny):
        if mpvClient.role != admin:
          mpvClient.role = if isJanny and mpvClient.name == jannyName: janny else: user
      Jannies(jannies):
        if jannies.len < 1:
          showEvent("There are currently no jannies")
        else:
          showEvent("Jannies: " & jannies.join(", "))
      PlaylistLoad(urls):
        server.playlist = urls
        clearPlaylist()
        for url in urls:
          player.playlistAppend(url)
        showEvent("Playlist loaded")
      PlaylistAdd(url):
        server.playlist.add url
        player.playlistAppend(url)
      PlaylistPlay(index):
        setState(server.playing, server.time, index=index)
        asyncCheck updateIndex()
      PlaylistClear:
        server.playlist.setLen(0)
        clearPlaylist()
        setState(false, 0.0)
        showEvent("Playlist cleared")
      Error(reason):
        showEvent(reason)
      Null: discard
      Auth: discard
      Success: discard
  close mpvClient.ws

proc main() {.async.} =
  server = Server(host: (if cfg.useTls: "wss://" else: "ws://") & cfg.address & "/ws")
  echo "Connecting to ", server.host

  try:
    mpvClient.ws = await newWebSocket(server.host)
    player = await startMpv(cfg.binPath)
    if player == nil: return
    asyncCheck handleMpv()
    asyncCheck updateTime()
    await handleServer()
  except WebSocketError, OSError:
    echo "Connection failed"
  if player != nil and player.running:
    close player

waitFor main()
