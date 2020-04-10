import asyncdispatch, json, strformat, strutils, sequtils, os
import ws
import protocol, mpv

type
  Server = object
    ws: WebSocket
    host: string
    clients: seq[string]
    playlist: seq[string]
    index: int
    playing: bool
    time: float

var
  server = Server(host: "127.0.0.1:9001/ws")
  player: Mpv
  role = user
  name = paramStr(1)
  messages: seq[string]
  loading = false
  reloading = false

proc join(): Future[bool] {.async.} =
  echo "Joining.."
  await server.ws.send(Auth.pack(name))
  let resp = unpack(await server.ws.receiveStrPacket())
  if resp.data != "success":
    echo "Join failed: " & resp.data
    return true

  if ":" in name:
    role = admin
    player.showEvent("Welcome to the Kinoplex, janny!")
  else:
    player.showEvent("Welcome to the Kinoplex!")

proc waitForLoad() =
  if loading:
    asyncCheck server.ws.send(Playing.pack("0"))

proc syncPlaying(playing: bool) =
  if role == admin:
    player.playing = playing
    asyncCheck server.ws.send(Playing.pack($ord(player.playing)))
  else:
    if server.playing != playing:
      player.setPlaying(server.playing)

proc syncTime(event: JsonNode) =
  if not event.hasKey("data"): return
  player.time = event["data"].getFloat(0)
  if role == admin:
    asyncCheck server.ws.send(Seek.pack($player.time))
    waitForLoad()
    server.time = player.time
  else:
    let diff = player.time - server.time
    if diff > 1 and diff != 0:
      player.showEvent("Syncing time")
      player.setTime(server.time)

proc syncIndex(index: int) =
  if index == -1: return
  if role == admin and index != server.index:
    player.showEvent("Playing " & server.playlist[index])
    asyncCheck server.ws.send(PlaylistPlay.pack($index))
    asyncCheck server.ws.send(Playing.pack("0"))
    server.index = index
    player.index = index
  else:
    if index != server.index:
      player.showEvent("Syncing playlist")
      player.playlistPlay(server.index)

proc setClients(users: seq[string]) =
  let printUsers = server.clients.len == 0
  server.clients = users
  if printUsers:
    player.showEvent("Users: " & server.clients.join(", "))

proc updateTime() {.async.} =
  while player.running:
    if not loading:
      player.getTime()
    await sleepAsync(500)

proc handleMessage(msg: string) =
  if msg.len == 0: return
  if msg[0] != '/':
    asyncCheck server.ws.send(Message.pack(msg))
    return

  let parts = msg.split(" ", maxSplit=1)
  case parts[0].strip(chars={'/'})
  of "i", "index":
    if parts.len == 1:
      player.showEvent("No index given")
    else:
      syncIndex(parseInt(parts[1]))
  of "a", "add":
    if parts.len == 1:
      player.showEvent("No url specified")
    else:
      asyncCheck server.ws.send(PlaylistAdd.pack(parts[1]))
  of "c", "clear":
    player.clearChat()
  of "l", "log":
    player.clearChat()
    let count = if parts.len > 1: parseInt parts[1] else: 6
    for m in messages[max(messages.len - count, 0) .. ^1]:
      player.showText(m)
  of "u", "users":
    server.clients.setLen(0)
    asyncCheck server.ws.send(Clients.pack(""))
  of "j", "janny":
    if parts.len == 1:
      player.showEvent("No user specified")
    elif parts[1] notin server.clients:
      player.showEvent("Invalid user")
    else:
      asyncCheck server.ws.send(Janny.pack(parts[1]))
  of "h":
    player.showText("help yourself")
  of "r", "reload":
    reloading = true
    loading = true
    waitForLoad()
    player.playlistClear()
    for i, url in server.playlist:
      player.playlistAppend(url)
    asyncCheck player.playlistPlayAndRemove(player.index + 1, 0)
  of "o", "open":
    if parts.len == 1 or parts[1].len == 0:
      player.showEvent("No file specified")
    reloading = true
    loading = true
    player.playlistAppend(parts[1])
    player.playlistMove(server.playlist.len, player.index)
    asyncCheck player.playlistPlayAndRemove(player.index, player.index + 1)
  of "e", "empty":
    asyncCheck server.ws.send(PlaylistClear.pack(""))
  else: discard

proc handleMpv() {.async.} =
  while player.running:
    let msg = try: await player.sock.recvLine()
              except: break

    if msg.len == 0:
      close player
      quit(0)

    let resp = parseJson(msg)
    case resp{"request_id"}.getInt(0)
    of 1: # seek
      if not reloading:
        syncTime(resp)
        continue
    else: discard

    let event = resp{"event"}.getStr
    case event
    of "pause", "unpause":
      let playing = event == "unpause"
      if not loading:
        syncPlaying(playing)
      player.playing = playing
    of "client-message":
      let args = resp{"args"}.getElems()
      if args.len == 0: continue
      case args[0].getStr()
      of "msg":
        handleMessage(args[1].getStr)
      else: discard
    of "property-change":
      if reloading:
        continue
      if resp{"name"}.getStr == "playlist-pos":
        syncIndex(resp{"data"}.getInt(-1))
    of "seek":
      player.getTime()
      loading = true
    of "start-file":
      loading = true
    of "file-loaded":
      loading = false
      if reloading:
        reloading = false
        player.setTime(server.time)
        player.setPlaying(server.playing)
      elif server.time != 0:
        player.setTime(server.time)
      syncPlaying(player.playing)
      syncIndex(player.index)
    of "playback-restart":
      if loading:
        syncPlaying(player.playing)
      loading = false
      reloading = false
    else: discard

proc handleServer() {.async.} =
  if await join(): return
  server.ws.setupPings(5)
  while server.ws.readyState == Open:
    let event = unpack(await server.ws.receiveStrPacket())
    case event.kind
    of PlaylistLoad:
      player.playlistClear()
      for v in event.data.split("\n"):
        server.playlist.add v
        player.playlistAppend(v)
      player.showEvent("Playlist loaded")
    of PlaylistAdd:
      server.playlist.add event.data
      player.playlistAppendPlay(event.data)
      player.showEvent("Added " & event.data)
    of PlaylistPlay:
      while loading:
        await sleepAsync(150)
      let n = parseInt(event.data)
      server.index = n
      player.playlistPlay(n)
      player.setPlaying(server.playing)
      player.setTime(server.time)
      player.showEvent("Playing " & server.playlist[n])
    of PlaylistClear:
      player.playlistClear()
      player.playlistRemove(0)
      server.playlist.setLen(0)
      player.playing = false
      server.playing = false
      server.time = 0.0
      player.showEvent("Playlist cleared")
    of Playing:
      server.playing = event.data == "1"
      player.setPlaying(server.playing)
      player.setTime(server.time)
    of Seek:
      server.time = parseFloat(event.data)
      if abs(player.time - server.time) > 1:
        player.setTime(server.time)
    of Message:
      if "<" in event.data:
        messages.add event.data
        player.showText(event.data)
      else:
        player.showEvent(event.data)
    of Clients:
      setClients(event.data.split("\n"))
    of Joined:
      server.clients.add event.data
      player.showEvent(event.data & " joined")
    of Left:
      server.clients.keepItIf(it != event.data)
      player.showEvent(event.data & " left")
    of Janny:
      role = janny
    of Null, Auth:
      discard
  close server.ws

proc main() {.async.} =
  try:
    server.ws = await newWebSocket("ws://" & server.host)
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
