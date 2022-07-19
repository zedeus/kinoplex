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

proc setState(playing: bool; time: float; index=(-1)) =
  if index > -1:
    server.index = index
  server.playing = playing
  server.time = time
  player.sendCmd(togglePlayer(playing))
  player.sendCmd(seek(time))
  player.playing = playing
  player.time = time

proc updateIndex() {.async.} =
  while loading:
    await sleepAsync(150)

  if server.playlist.len == 0:
    return
  if server.index > server.playlist.high:
    showEvent("Loading went wrong")
    return
  let url = server.playlist[server.index]
  player.sendCmd(playUrl(url, 0))
  showEvent("Playing " & url)

# proc syncPlaying(playing: bool) =
#   if role == admin:
#     player.playing = playing
#     server.playing = playing
#     server.send(State(not loading and player.playing, server.time))
#   else:
#     if server.playing != playing:
#       player.sendCmd(togglePlayer(server.playing))
#       player.playing = server.playing

# proc syncTime(time: float) =
#   player.time = time
#   let diff = player.time - server.time
#   if diff > 1:
#     showEvent("Syncing time")
#     player.sendCmd(seek(server.time))

# proc syncIndex(index: int) =
#   if index == -1: return
#   if index != server.index and server.playlist.len > 0:
#     setState(server.playing, server.time, index=server.index)
#     if not loading:
#       asyncCheck updateIndex()

proc updateTime() {.async.} =
  while player.connected:
    if not loading:
      player.sendCmd(getTime())
    await sleepAsync(500)

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
      Joined(name, role):
        showEvent(&"{name} joined as {role}")
      Left(name):
        showEvent(name & " left")
      Renamed(oldName, newName):
        if oldName == name: name = newName
      PlaylistLoad(urls):
        server.playlist = urls
        clearPlaylist()
        # for url in urls:
        #   player.playlistAppend(url)
        showEvent("Playlist loaded")
      PlaylistAdd(url):
        server.playlist.add url
        # player.playlistAppendPlay(url)
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
    player = await connect(cfg.kodiHost)
    if player == nil: return
    # asyncCheck handleKodi()
    asyncCheck updateTime()
    await handleServer()
  except WebSocketError, OSError:
    echo "Connection failed"
  if player != nil and player.connected:
    player.connected = false
    close player.ws

waitFor main()
