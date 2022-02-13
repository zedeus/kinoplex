import std/[os, asyncdispatch, json, strformat, strutils]
import ws
import mpv/[mpv, config], protocol

type
  Server = object
    ws: WebSocket
    host: string
    playlist: seq[string]
    index: int
    playing: bool
    time: float

let
  cfg = getConfig()

var
  name = cfg.username
  role = user
  server: Server
  player: Mpv
  messages: seq[string]
  loading = false
  reloading = false

proc killKinoplex() =
  echo "Leaving"
  close player
  close server.ws

proc send(s: Server; data: Event) =
  asyncCheck s.ws.send($(%data))

proc showText(text: string) =
  player.showText(text)
  stdout.write(text, "\n")
  messages.add text

proc showEvent(text: string) =
  player.showEvent(text)
  stdout.write(text, "\n")

proc join(): Future[bool] {.async.} =
  echo "Joining.."
  await server.ws.send($(%Auth(name, cfg.password)))

  let resp = unpack(await server.ws.receiveStrPacket())
  match resp:
    Joined(newName, newRole):
      name = newName
      if newRole != user:
        role = newRole
        showEvent(&"Welcome to the kinoplex, {role}!")
      else:
        showEvent("Welcome to the kinoplex!")
      if cfg.password.len > 0 and newRole == user:
        showEvent("Admin authentication failed")
    Error(reason):
      showEvent("Join failed: " & reason)
      result = true
    _: discard

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
  if server.index > server.playlist.high:
    showEvent("Loading went wrong")
    return
  player.playlistPlay(server.index)
  showEvent("Playing " & server.playlist[server.index])

proc syncPlaying(playing: bool) =
  if role == admin:
    player.playing = playing
    server.playing = playing
    server.send(State(not loading and player.playing, server.time))
  else:
    if server.playing != playing:
      player.setPlaying(server.playing)

proc syncTime(time: float) =
  player.time = time
  if role == admin:
    server.time = player.time
    server.send(State(not loading and player.playing, server.time))
  else:
    let diff = player.time - server.time
    if diff > 1:
      showEvent("Syncing time")
      player.setTime(server.time)

proc syncIndex(index: int) =
  if index == -1: return
  if role == admin and index != server.index:
    if index > server.playlist.high:
      showEvent(&"Syncing index wrong {index} > {server.playlist.high}")
      return
    showEvent("Playing " & server.playlist[index])
    server.send(PlaylistPlay(index))
    server.send(State(false, 0))
    setState(false, 0, index=index)
  else:
    if index != server.index and server.playlist.len > 0:
      setState(server.playing, server.time, index=server.index)
      if not loading:
        asyncCheck updateIndex()

proc reloadPlayer() =
  reloading = true
  if role == admin:
    server.send(State(false, player.time))
  clearPlaylist()
  for url in server.playlist:
    player.playlistAppend(url)
  setState(server.playing, server.time)
  asyncCheck updateIndex()

proc validUrl(url: string; acceptFile=false): bool =
  url.len > 0 and "\n" notin url and (acceptFile or "http" in url)

proc updateTime() {.async.} =
  while player.running:
    if not loading:
      player.getTime()
    await sleepAsync(500)

proc handleMessage(msg: string) {.async.} =
  if msg.len == 0: return
  if msg[0] != '/':
    server.send(Message(name, msg[0..min(280, msg.high)]))
    showText(&"{name}: {msg}")
    return

  let parts = msg.split(" ", maxSplit=1)
  case parts[0].strip(chars={'/'})
  of "i", "index":
    if parts.len == 1:
      showEvent("No index given")
    elif role != admin:
      showEvent("You don't have permission")
    else:
      syncIndex(parseInt(parts[1]))
  of "a", "add":
    if parts.len == 1 or not validUrl(parts[1]):
      showEvent("No url specified")
    else:
      server.send(PlaylistAdd(parts[1]))
  of "o", "open":
    if parts.len == 1 or not validUrl(parts[1], acceptFile=true):
      showEvent("No file or url specified")
    elif "http" notin parts[1] and not fileExists(parts[1]):
      showEvent("File doesn't exist")
    elif server.playlist.len == 0:
      showEvent("No file is playing")
    else:
      reloading = true
      loading = true
      if role == admin:
        server.send(State(false, player.time))
      player.playlistAppend(parts[1])
      player.playlistMove(server.playlist.len, player.index)
      asyncCheck player.playlistPlayAndRemove(player.index, player.index + 1)
  of "c", "clear":
    player.clearChat()
  of "l", "log":
    player.clearChat()
    let count = if parts.len > 1: parseInt parts[1] else: 6
    for m in messages[max(messages.len - count, 0) .. ^1]:
      player.showText(m)
  of "u", "users":
    server.send(Clients(@[]))
  of "j", "janny":
    if parts.len == 1:
      showEvent("No user specified")
    else:
      server.send(Janny(parts[1], true))
  of "js", "jannies":
    server.send(Jannies(@[]))
  of "h":
    player.showText("help yourself")
  of "r", "reload":
    reloadPlayer()
  of "e", "empty":
    server.send(PlaylistClear())
  of "n", "rename":
    if parts.len == 1:
      showEvent("No name specified")
    else:
      server.send(Renamed(name, parts[1]))
  of "restart":
    if role == admin:
      server.send(State(false, player.time))
    await player.restart()
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
      if role == admin:
        server.send(State(false, player.time))
      await player.restart()
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
            server.send(PlaylistAdd(url))
      of "quit":
        killKinoplex()
      else: discard
    of "idle":
      # either failed to load or reset
      loading = false
    else: discard

proc handleServer() {.async.} =
  if await join(): return
  server.ws.setupPings(5)
  while server.ws.readyState == Open:
    let event = unpack(await server.ws.receiveStrPacket())
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
        if oldName == name: name = newName
      Janny(jannyName, isJanny):
        if role != admin:
          role = if isJanny and name == jannyName: janny else: user
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
        player.playlistAppendPlay(url)
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
  close server.ws

proc main() {.async.} =
  server = Server(host: (if cfg.useTls: "wss://" else: "ws://") & cfg.address)
  try:
    server.ws = await newWebSocket(server.host)
    player = await startMpv()
    if player == nil: return
    asyncCheck handleMpv()
    asyncCheck updateTime()
    await handleServer()
  except WebSocketError, OSError:
    echo "Connection failed"
  if player.running:
    close player

waitFor main()
