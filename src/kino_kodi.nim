import std/[os, asyncdispatch, json, strformat, strutils]
import ws
import kodi/[kodi, jsonrpc, config], protocol

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
  player: Kodi
  messages: seq[string]
  loading = false
  reloading = false

proc killKinoplex() =
  echo "Leaving"
  player.connected = false
  close player.ws
  close server.ws

proc send(s: Server; data: Event) =
  asyncCheck s.ws.send($(%data))

proc showText(text: string) =
  let prevMsg = if messages.len > 0: messages[^1] else: ""
  player.sendCmd(showMessage(text, prevMsg))
  stdout.write(text, "\n")
  messages.add text

proc showEvent(text: string) =
  player.sendCmd(showMessage(text, "System"))
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
    Error(reason):
      showEvent("Join failed: " & reason)
      result = true
    _: discard

proc clearPlaylist() =
  player.sendCmd(stop())
  loading = false

proc seekTo(time: float) =
  if abs(time - player.time) > 3:
    showEvent("Syncing time " & $time)
    player.sendCmd(seek(time + 0.5))

proc setState(playing: bool; time: float; index=(-1)) =
  if index > -1:
    server.index = index
  server.playing = playing
  server.time = time
  if not loading:
    if player.playing != playing:
      player.sendCmd(togglePlayer(playing))
    seekTo(time)

proc updateIndex() {.async.} =
  while loading:
    await sleepAsync(150)

  if server.playlist.len == 0:
    return
  if server.index > server.playlist.high:
    showEvent("Loading went wrong")
    return
  let url = server.playlist[server.index]
  player.sendCmd(playUrl(url, server.time))
  showEvent("Playing " & url)
  loading = true

proc syncPlaying(playing: bool) =
  if server.playing != playing:
    player.sendCmd(togglePlayer(server.playing))
    player.playing = server.playing

proc syncTime(time: float) =
  player.time = time
  seekTo(time)

proc updateTime() {.async.} =
  while player.connected:
    if not loading:
      player.sendCmd(getTime())
    await sleepAsync(500)

proc handleKodi() {.async.} =
  player.ws.setupPings(5)
  while player.ws.readyState == Open:
    let raw = await player.ws.receiveStrPacket()
    if raw[0] != '{':
      continue

    let event = parseJson(raw)
    if event.hasKey("error"):
      echo "ERROR: ", event
      continue

    if event.hasKey("result"):
      let res = event["result"]
      if res.kind == JObject and res.hasKey("time"):
        syncTime(timeToMs(res["time"]))
      continue

    echo "notification: ", loading, " ", event["method"]

    case event["method"].getStr
    of "Player.OnPlay":
      loading = true
      player.playing = false
      player.time = 0
    of "Player.OnAVStart":
      loading = false
      setState(server.playing, server.time)
      echo "playback started"
    of "Player.OnAVChange":
      if not loading:
        syncPlaying(true)
    of "Player.OnResume":
      syncPlaying(true)
    of "Player.OnPause":
      syncPlaying(false)
    of "Player.OnStop":
      showEvent("stopped")
      asyncCheck updateIndex()
    of "Player.OnSeek":
      let item = event{"params", "data", "player"}
      player.time = timeToMs(item["time"])
    of "Playlist.OnClear": discard
    of "Playlist.OnAdd": discard
    else:
      echo "unhandled: ", event
  close player.ws

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
        echo "setState p:", playing, " t:", time
        setState(playing, time)
      PlaylistLoad(urls):
        if server.playlist.len > 0:
          clearPlaylist()
        server.playlist = urls
        showEvent("Playlist loaded")
      PlaylistAdd(url):
        server.playlist.add url
        if server.playlist.len == 1:
          asyncCheck updateIndex()
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
      Joined(name, role):
        showEvent(&"{name} joined as {role}")
      Left(name):
        showEvent(name & " left")
      Renamed(oldName, newName):
        if oldName == name: name = newName
      Janny: discard
      Jannies: discard
      Clients: discard
      Null: discard
      Auth: discard
      Success: discard
  close server.ws

proc main() {.async.} =
  server = Server(host: (if cfg.useTls: "wss://" else: "ws://") & cfg.address & "/ws")
  echo "Connecting to ", server.host

  try:
    server.ws = await newWebSocket(server.host)
    echo "connected to server"
    player = await connect(cfg.kodiHost)
    echo "connected to kodi"
    if player == nil: return
    asyncCheck handleKodi()
    asyncCheck updateTime()
    await handleServer()
  except WebSocketError, OSError:
    echo "Connection failed"
  if player != nil and player.connected:
    player.connected = false
    close player.ws

waitFor main()
