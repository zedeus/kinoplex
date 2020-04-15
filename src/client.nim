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
  password = if paramCount() > 1: paramStr(2) else: ""
  messages: seq[string]
  loading = false
  reloading = false

template send(s: Server; data: string) =
  asyncCheck s.ws.send(data)

proc showText(text: string) =
  player.showText(text)
  stdout.write(text, "\n")
  messages.add text

proc showEvent(text: string) =
  player.showEvent(text)
  stdout.write(text, "\n")

proc join(): Future[bool] {.async.} =
  echo "Joining.."
  let login = %*{"name": name}
  if password.len > 0:
    login{"password"} = %password
  await server.ws.send(Auth.pack(login))

  let resp = unpack(await server.ws.receiveStrPacket())
  if not resp.data{"joined"}.getBool:
    echo "Join failed: " & resp.data{"reason"}.getStr
    return true

  if password.len > 0:
    role = admin
    showEvent(&"Welcome to the Kinoplex, {role}!")
  else:
    showEvent("Welcome to the Kinoplex!")

proc syncPlaying(playing: bool) =
  if role == admin:
    player.playing = playing
    server.playing = playing
    server.send(state(not loading and player.playing, server.time))
  else:
    if server.playing != playing:
      player.setPlaying(server.playing)

proc syncTime(time: float) =
  player.time = time
  if role == admin:
    server.send(state(not loading and player.playing, player.time))
    server.time = player.time
  else:
    let diff = player.time - server.time
    if diff > 1 and diff != 0:
      showEvent("Syncing time")
      player.setTime(server.time)

proc syncIndex(index: int) =
  if index == -1: return
  if role == admin and index != server.index:
    showEvent("Playing " & server.playlist[index])
    server.send(PlaylistPlay.pack(%*{"index": index}))
    server.send(state(false, 0))
    server.index = index
    player.index = index
  else:
    if index != server.index and server.playlist.len > 0:
      showEvent("Syncing playlist")
      player.playlistPlay(server.index)

proc setClients(users: seq[string]) =
  let printUsers = server.clients.len == 0
  server.clients = users
  if printUsers:
    showEvent("Users: " & server.clients.join(", "))

proc reloadPlayer() =
  reloading = true
  loading = true
  if role == admin:
    server.send(state(false, player.time))
  player.playlistClear()
  for i, url in server.playlist:
    player.playlistAppend(url)
  player.playlistPlay(server.index)
  player.setPlaying(server.playing)
  player.setTime(server.time)

proc updateTime() {.async.} =
  while player.running:
    if not loading:
      player.getTime()
    await sleepAsync(500)

proc validUrl(url: string; acceptFile=false): bool =
  url.len > 0 and "\n" notin url and (acceptFile or "http" in url)

proc handleMessage(msg: string) =
  if msg.len == 0: return
  if msg[0] != '/':
    server.send(Message.pack(%*{"text": msg}))
    showText(&"<{name}> {msg}")
    return

  let parts = msg.split(" ", maxSplit=1)
  case parts[0].strip(chars={'/'})
  of "i", "index":
    if parts.len == 1:
      showEvent("No index given")
    else:
      syncIndex(parseInt(parts[1]))
  of "a", "add":
    if parts.len == 1 or not validUrl(parts[1]):
      showEvent("No url specified")
    else:
      server.send(PlaylistAdd.pack(%*{"url": parts[1]}))
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
        server.send(state(false, player.time))
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
    server.clients.setLen(0)
    server.send(Clients.pack(JsonNode()))
  of "j", "janny":
    if parts.len == 1:
      showEvent("No user specified")
    elif parts[1] notin server.clients:
      showEvent("Invalid user")
    else:
      server.send(Janny.pack(%*{"name": parts[1]}))
  of "h":
    player.showText("help yourself")
  of "r", "reload":
    reloadPlayer()
  of "e", "empty":
    server.send(PlaylistClear.pack(JsonNode()))
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
    of "playback-restart":
      loading = false
      if reloading:
        reloading = false
        player.setPlaying(server.playing)
      if server.time != 0:
        player.setTime(server.time)
      if server.time == player.time:
        syncPlaying(player.playing)
      syncIndex(player.index)
    else: discard

proc handleServer() {.async.} =
  if await join(): return
  server.ws.setupPings(5)
  while server.ws.readyState == Open:
    let event = unpack(await server.ws.receiveStrPacket())
    case event.kind
    of PlaylistLoad:
      player.playlistClear()
      for url in event.data{"urls"}.getElems().mapIt(getStr(it)):
        server.playlist.add url
        player.playlistAppend(url)
      showEvent("Playlist loaded")
    of PlaylistAdd:
      let url = event.data{"url"}.getStr
      server.playlist.add url
      player.playlistAppendPlay(url)
      showEvent("Added " & url)
    of PlaylistPlay:
      while loading:
        await sleepAsync(150)
      let n = event.data{"index"}.getInt
      server.index = n
      player.playlistPlay(n)
      player.setPlaying(server.playing)
      player.setTime(server.time)
      showEvent("Playing " & server.playlist[n])
    of PlaylistClear:
      player.playlistClear()
      server.playlist.setLen(0)
      player.playing = false
      server.playing = false
      server.time = 0.0
      showEvent("Playlist cleared")
    of State:
      server.playing = event.data{"playing"}.getBool
      server.time = event.data{"time"}.getFloat
      player.setPlaying(server.playing)
      player.setTime(server.time)
    of Message:
      let msg = event.data{"text"}.getStr
      if "<" in msg:
        showText(msg)
      else:
        showEvent(msg)
    of Clients:
      setClients(event.data{"clients"}.getElems.mapIt(getStr(it)))
    of Joined:
      let name = event.data{"name"}.getStr
      server.clients.add name
      showEvent(name & " joined")
    of Left:
      let name = event.data{"name"}.getStr
      server.clients.keepItIf(it != name)
      showEvent(name & " left")
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
