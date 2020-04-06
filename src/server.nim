import asyncdispatch, asynchttpserver, sequtils, strutils, strformat
import ws
import protocol

type
  Client = ref object
    id: int
    name: string
    admin: bool
    ws: WebSocket

var
  clients: seq[Client]
  password = "1337"
  playing: bool
  playlist: seq[string]
  playlistIndex = 0
  globalId = 0
  timestamp = 0.0

template safeSend(ws, msg) =
  if ws.readyState == Open:
    asyncCheck ws.send(msg)

proc broadcast(msg: string; skip=(-1)) =
  for c in clients:
    if c.id == skip: continue
    c.ws.safeSend(msg)

proc authorize(client: Client; ev: Event) {.async.} =
  if clients.anyIt(it.name == ev.data):
    client.ws.safeSend(Auth.pack("name already taken"))
    return
  elif ":" in ev.data:
    let auth = ev.data.split(":", 1)
    if auth[1] != password:
      client.ws.safeSend(Auth.pack("wrong admin password"))
      return
    client.name = auth[0]
    client.admin = true
    echo "Admin authenticated"
  else:
    client.name = ev.data

  if client.name.len == 0:
    client.ws.safeSend(Auth.pack("name empty"))
    return

  client.ws.safeSend(Auth.pack("success"))
  client.id = globalId
  inc globalId
  clients.add client
  broadcast(Joined.pack(client.name), skip=client.id)
  echo &"New client: {client.name} ({client.id})"

  if playlist.len > 0:
    client.ws.safeSend(PlaylistLoad.pack(playlist.join("\n")))
    client.ws.safeSend(PlaylistPlay.pack($playlistIndex))
  client.ws.safeSend(Seek.pack($timestamp))
  client.ws.safeSend(State.pack(if playing: "1" else: "0"))
  client.ws.safeSend(Clients.pack(clients.mapIt(it.name).join("\n")))

proc handle(client: Client; ev: Event) {.async.} =
  if ev.kind notin {Auth, Seek}:
    echo "(", client.name, ") ", ev.kind, ": ", ev.data

  template checkPermission() =
    if not client.admin:
      client.ws.safeSend(Message.pack("You don't have permission"))
      return

  case ev.kind
  of Auth:
    asyncCheck client.authorize(ev)
  of Message:
    broadcast(Message.pack(&"<{client.name}> {ev.data}"))
  of Clients:
    client.ws.safeSend(Clients.pack(clients.mapIt(it.name).join("\n")))
  of Seek, State:
    checkPermission()
    if ev.kind == State: playing = ev.data == "1"
    elif ev.kind == Seek: timestamp = parseFloat(ev.data)
    broadcast(pack ev, skip=client.id)
  of PlaylistLoad:
    client.ws.safeSend(PlaylistLoad.pack(playlist.join("\n")))
  of PlaylistClear:
    playlist.setLen(0)
    broadcast(pack ev)
  of PlaylistAdd:
    checkPermission()
    playlist.add ev.data
    broadcast(PlaylistAdd.pack(ev.data))
  of PlaylistPlay:
    checkPermission()
    let n = parseInt(ev.data)
    if n > playlist.high:
      client.ws.safeSend(Message.pack("Index too high"))
    else:
      playlistIndex = n
      broadcast(pack ev, skip=client.id)
      broadcast(Seek.pack("0.0"))
  of Admin:
    checkPermission()
    for c in clients:
      if c.name != ev.data: continue
      if c.admin:
        client.ws.safeSend(Message.pack(c.name & " is already admin"))
        return
      c.admin = true
      broadcast(Message.pack(c.name & " granted admin"))
      c.ws.safeSend(Admin.pack(""))
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
      broadcast(Left.pack(client.name))
      broadcast(State.pack("0"))

var server = newAsyncHttpServer()
waitFor server.serve(Port(9001), cb)
