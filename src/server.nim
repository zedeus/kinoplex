import asyncdispatch, asynchttpserver, sequtils, strutils, strformat
import ws
import protocol

type
  Client = ref object
    id: int
    name: string
    role: Role
    ws: WebSocket

var
  clients: seq[Client]
  password = "1337"
  playing: bool
  playlist: seq[string]
  playlistIndex = 0
  globalId = 0
  timestamp = 0.0
  pauseOnLeave = true
  pauseOnChange = false

template send(client, msg) =
  try:
    if client.ws.readyState == Open:
      asyncCheck client.ws.send(msg)
  except WebSocketError:
    discard

proc broadcast(msg: string; skip=(-1)) =
  for c in clients:
    if c.id == skip: continue
    c.send(msg)

template auth(joined, reason): string =
  Auth.pack(%*{"joined": joined, "reason": reason})

template message(text): string =
  Message.pack(%*{"text": text})

template state(): string =
  State.pack(%*{"playing": playing, "time": timestamp})

proc authorize(client: Client; ev: Event) {.async.} =
  let pass = ev.data{"password"}.getStr
  if pass.len > 0:
    if pass != password:
      client.send(auth(false, "wrong admin password"))
      return
    else:
      client.role = admin

  client.name = ev.data{"name"}.getStr
  if clients.anyIt(it.name == client.name):
    client.send(auth(false, "name already taken"))
    return
  if client.name.len == 0:
    client.send(auth(false, "name empty"))
    return

  client.send(auth(true, ""))
  client.id = globalId
  inc globalId
  clients.add client
  broadcast(Joined.pack(%*{"name": client.name}), skip=client.id)
  echo &"New client: {client.name} ({client.id})"

  if playlist.len > 0:
    client.send(PlaylistLoad.pack(%*{"urls": playlist}))
    client.send(PlaylistPlay.pack(%*{"index": playlistIndex}))
  client.send(state())
  client.send(Clients.pack(%*{"clients": clients.mapIt(it.name)}))

proc handle(client: Client; ev: Event) {.async.} =
  if ev.kind notin {Auth}:
    echo "(", client.name, ") ", ev.kind, ": ", ev.data

  template checkPermission(minRole) =
    if client.role < minRole:
      client.send(message("You don't have permission"))
      return

  case ev.kind
  of Auth:
    asyncCheck client.authorize(ev)
  of Message:
    let text = ev.data{"text"}.getStr
    broadcast(message(&"<{client.name}> {text}"), skip=client.id)
  of Clients:
    client.send(Clients.pack(%*{"clients": clients.mapIt(it.name)}))
  of State:
    checkPermission(admin)
    playing = ev.data{"playing"}.getBool
    timestamp = ev.data{"time"}.getFloat
    broadcast(pack ev, skip=client.id)
  of PlaylistLoad:
    client.send(PlaylistLoad.pack(%*{"urls": playlist}))
  of PlaylistClear:
    checkPermission(admin)
    playlist.setLen(0)
    timestamp = 0.0
    playing = false
    broadcast(pack ev)
  of PlaylistAdd:
    checkPermission(janny)
    let url = ev.data{"url"}.getStr
    if "http" notin url:
      client.send(message("Invalid url"))
    else:
      playlist.add url
      broadcast(PlaylistAdd.pack(%*{"url": url}))
      broadcast(message(&"{client.name} added {url}"))
  of PlaylistPlay:
    checkPermission(admin)
    let n = ev.data{"index"}.getInt
    if n > playlist.high:
      client.send(message("Index too high"))
    elif n < 0:
      client.send(message("Index too low"))
    else:
      playlistIndex = n
      timestamp = 0
      if pauseOnChange:
        playing = false
      broadcast(pack ev, skip=client.id)
      broadcast(state())
  of Janny:
    checkPermission(admin)
    for c in clients:
      if c.name != ev.data{"name"}.getStr: continue
      if c.role == janny:
        client.send(message(c.name & " is already a janny"))
        return
      c.role = janny
      broadcast(message(c.name & " became a janny"))
      c.send(Janny.pack(JsonNode()))
  else: echo "unknown: ", ev

proc cb(req: Request) {.async, gcsafe.} =
  if req.url.path == "/ws":
    var client: Client
    try:
      client = Client(ws: await newWebSocket(req))
      while client.ws.readyState == Open:
        let msg = await client.ws.receiveStrPacket()
        if msg.len > 0:
          await client.handle(unpack msg)
    except WebSocketError:
      echo &"socket closed: {client.name} ({client.id})"
      clients.keepItIf(it != client)
      if client.name.len > 0:
        broadcast(Left.pack(%*{"name": client.name}))
        if pauseOnLeave:
          playing = false
          broadcast(state())

var server = newAsyncHttpServer()
waitFor server.serve(Port(9001), cb)
