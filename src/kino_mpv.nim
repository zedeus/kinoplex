import std/[os, asyncdispatch, json, strformat, strutils]
import ws
import lib/[protocol, kino_client, utils]
import mpv/[mpv, config]

type
  MpvClient = ref object of Client

let
  cfg = getConfig()

var
  client = MpvClient(name: cfg.username)
  server: Server
  player: Mpv
  loading = false
  reloading = false

proc killKinoplex() =
  echo "Leaving"
  close player
  close client.ws

template sendEvent(client: MpvClient, event: Event): untyped =
  safeAsync client.send(event)

proc showText(msg: Msg) =
  let text = &"{msg.name}: {msg.text}"
  player.showText(text)
  stdout.write(text, "\n")

proc showEvent(text: string) =
  player.showEvent(text)
  stdout.write(text, "\n")

proc showChatLog(count=6) =
  player.clearChat()
  for m in server.recentMsgs(count):
    showText(m)

proc join(): Future[bool] {.async.} =
  var error: bool
  
  echo "Joining.."
  client.authenticate(cfg.password, resp):
    match resp:
      Joined(newName, newRole):
        client.name = newName
        if newRole != user:
          client.role = newRole
          showEvent(&"Welcome to the kinoplex, {client.role}!")
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
  showEvent("Playing " & server.playlist[server.index].url)

proc syncPlaying(playing: bool) =
  if client.role == admin:
    player.playing = playing
    server.playing = playing
    client.sendEvent(State(not loading and player.playing, server.time))
  else:
    if server.playing != playing:
      player.setPlaying(server.playing)

proc syncTime(time: float) =
  player.time = time
  if client.role == admin:
    server.time = player.time
    client.sendEvent(State(not loading and player.playing, server.time))
  else:
    let diff = player.time - server.time
    if diff > 1:
      showEvent("Syncing time")
      player.setTime(server.time)

proc syncIndex(index: int) =
  if index == -1: return
  if client.role == admin and index != server.index:
    if index > server.playlist.high:
      showEvent(&"Syncing index wrong {index} > {server.playlist.high}")
      return
    showEvent("Playing " & server.playlist[index].url)
    client.sendEvent(PlaylistPlay(index))
    client.sendEvent(State(false, 0))
    setState(false, 0, index=index)
  else:
    if index != server.index and server.playlist.len > 0:
      setState(server.playing, server.time, index=server.index)
      if not loading:
        safeAsync updateIndex()

proc reloadPlayer() =
  reloading = true
  if client.role == admin:
    client.sendEvent(State(false, player.time))
  clearPlaylist()
  for item in server.playlist:
    player.playlistAppend(item.url)
  setState(server.playing, server.time)
  safeAsync updateIndex()
  showChatLog()

proc updateTime() {.async.} =
  while player.running:
    if not loading:
      player.getTime()
    await sleepAsync(500)

proc handleMessage(text: string) {.async.} =
  if text.len == 0: return
  if text[0] != '/':
    let msg = Msg(name: client.name, text: text[0..min(280, text.high)])
    client.sendEvent(Message(client.name, msg.text))
    showText(msg)
    server.messages.add msg
    return

  let parts = text.split(" ", maxSplit=1)
  case parts[0].strip(chars={'/'})
  of "i", "index":
    if parts.len == 1:
      showEvent("No index given")
    elif client.role != admin:
      showEvent("You don't have permission")
    else:
      syncIndex(parseInt(parts[1]))
  of "a", "add":
    if parts.len == 1 or not validUrl(parts[1]):
      showEvent("No url specified")
    else:
      client.sendEvent(PlaylistAdd(MediaItem(url: parts[1])))
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
      if client.role == admin:
        client.sendEvent(State(false, player.time))
      player.playlistAppend(parts[1])
      player.playlistMove(server.playlist.len, player.index)
      safeAsync player.playlistPlayAndRemove(player.index, player.index + 1)
  of "c", "clear":
    player.clearChat()
  of "l", "log":
    let count = if parts.len > 1: parseInt parts[1] else: 6
    showChatLog(count)
  of "u", "users":
    client.sendEvent(Clients(@[]))
  of "j", "janny":
    if parts.len == 1:
      showEvent("No user specified")
    else:
      client.sendEvent(Janny(parts[1], true))
  of "unjanny":
    if parts.len == 1:
      showEvent("No user specified")
    else:
      client.sendEvent(Janny(parts[1], false))
  of "js", "jannies":
    client.sendEvent(Jannies(@[]))
  of "h":
    player.showText("help yourself")
  of "r", "reload":
    reloadPlayer()
  of "e", "empty":
    client.sendEvent(PlaylistClear())
  of "n", "rename":
    if parts.len == 1:
      showEvent("No name specified")
    else:
      client.sendEvent(Renamed(client.name, parts[1]))
  of "restart":
    if client.role == admin:
      client.sendEvent(State(false, player.time))
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
      if client.role == admin:
        client.sendEvent(State(false, player.time))
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
            client.sendEvent(PlaylistAdd(MediaItem(url: url)))
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
  client.ws.setupPings(5)
  client.poll(event):
    match event:
      Message(name, text):
        if name == "server":
          showEvent(text)
        else:
          let msg = Msg(name: name, text: text)
          showText(msg)
          server.messages.add msg
      State(playing, time):
        setState(playing, time)
      Clients(names):
        showEvent("Users: " & names.join(", "))
      Joined(name, role):
        showEvent(&"{name} joined as {role}")
      Left(name):
        showEvent(name & " left")
      Renamed(oldName, newName):
        if oldName == client.name: client.name = newName
      Janny(jannyName, isJanny):
        if client.role != admin:
          client.role = if isJanny and client.name == jannyName: janny else: user
      Jannies(jannies):
        if jannies.len < 1:
          showEvent("There are currently no jannies")
        else:
          showEvent("Jannies: " & jannies.join(", "))
      PlaylistLoad(playlist):
        server.playlist = playlist
        clearPlaylist()
        for item in playlist:
          player.playlistAppend(item.url)
        showEvent("Playlist loaded")
      PlaylistAdd(item):
        server.playlist.add item
        player.playlistAppend(item.url)
      PlaylistPlay(index):
        setState(server.playing, server.time, index=index)
        safeAsync updateIndex()
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
  close client.ws

proc main() {.async.} =
  server = Server(host: getServerUri(cfg.useTls, cfg.address))
  echo "Connecting to ", server.host

  try:
    client.ws = await newWebSocket(server.host)
    player = await startMpv(cfg.binPath)
    if player == nil: return
    safeAsync handleMpv()
    safeAsync updateTime()
    await handleServer()
  except WebSocketError, OSError:
    echo "Connection failed"
  if player != nil and player.running:
    close player

waitFor main()
