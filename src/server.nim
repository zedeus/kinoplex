import asyncdispatch, asynchttpserver, sequtils, strutils, strformat, strtabs
import ws
import protocol
import os

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
  httpCache = newStringTable()

template send(client, msg) =
  try:
    if client.ws.readyState == Open:
      asyncCheck client.ws.send($(%msg))
  except WebSocketError:
    discard

proc broadcast(msg: Event; skip=(-1)) =
  for c in clients:
    if c.id == skip: continue
    c.send(msg)

proc authorize(client: Client; name, pass: string) {.async.} =
  if pass.len > 0 and pass == password:
    client.role = admin

  client.name = name
  if client.name.len == 0:
    client.send(Error("name empty"))
    return
  if client.name == "server":
    client.send(Error("spoofing the server is not allowed"))
    return
  if clients.anyIt(it.name == client.name):
    client.send(Error("name already taken"))
    return

  client.send(Joined(client.name, client.role))
  client.id = globalId
  inc globalId
  clients.add client
  broadcast(Joined(client.name, client.role), skip=client.id)
  echo &"New client: {client.name} ({client.id})"

  if playlist.len > 0:
    client.send(PlaylistLoad(playlist))
    client.send(PlaylistPlay(playlistIndex))
  client.send(State(playing, timestamp))
  client.send(Clients(clients.mapIt(it.name)))

proc handle(client: Client; ev: Event) {.async.} =
  # if ev.kind != EventKind.Auth:
  #   echo "(", client.name, ") ", ev

  template checkPermission(minRole) =
    if client.role < minRole:
      client.send(Message("server", "You don't have permission"))
      return

  match ev:
    Auth(name, pass):
      asyncCheck client.authorize(name, pass)
    Message(_, text):
      broadcast(Message(client.name, text), skip=client.id)
    Clients:
      client.send(Clients(clients.mapIt(it.name)))
    State(state, time):
      checkPermission(admin)
      playing = state
      timestamp = time
      broadcast(ev, skip=client.id)
    PlaylistLoad:
      client.send(PlaylistLoad(playlist))
    PlaylistClear:
      checkPermission(admin)
      playlist.setLen(0)
      playing = false
      timestamp = 0.0
      broadcast(ev)
    PlaylistAdd(url):
      checkPermission(janny)
      if "http" notin url:
        client.send(Message("server", "Invalid url"))
      else:
        playlist.add url
        broadcast(PlaylistAdd(url))
        broadcast(Message("server", &"{client.name} added {url}"))
    PlaylistPlay(index):
      checkPermission(admin)
      if index > playlist.high:
        client.send(Message("server", "Index too high"))
      elif index < 0:
        client.send(Message("server", "Index too low"))
      else:
        playlistIndex = index
        if pauseOnChange:
          playing = false
        timestamp = 0
        broadcast(ev, skip=client.id)
        broadcast(State(playing, timestamp))
    Janny(name, state):
      checkPermission(admin)
      var found = false
      for c in clients:
        if c.name != name: continue
        found = true
        if state and c.role == janny:
          client.send(Message("server", c.name & " is already a janny"))
        elif state and c.role == user:
          c.role = janny
          c.send(Janny(c.name, true))
          broadcast(Message("server", c.name & " became a janny"))
        elif not state and c.role == janny:
          c.role = user
          c.send(Janny(c.name, false))
          broadcast(Message("server", c.name & " is no longer a janny"))
      if not found:
        client.send(Error("Invalid user"))
    _: echo "unknown: ", ev

proc serveFile(req: Request) {.async.} =
  var
    file: string
    content: string
    code = Http200

  let
    root = "static"
    index = root & "/client.html"
    path = req.url.path
    fullPath = root & path
    error404 = "File not found (404)"

  if existsDir(root):
    if path == "/" and existsFile(index):
      file = index;
    if existsFile(full_path):
      file = full_path

  if file.len > 0:
    if file notin httpCache:
      httpCache[file] = file.readFile
    content = httpCache[file]
  else:
    content = error404
    code = Http404

  await req.respond(code, content)

proc cb(req: Request) {.async, gcsafe.} =
  if req.url.path == "/ws":
    var client = Client()
    try:
      client.ws = await newWebSocket(req)
      while client.ws.readyState == Open:
        let msg = await client.ws.receiveStrPacket()
        if msg.len > 0:
          await client.handle(unpack msg)
    except WebSocketError:
      echo &"socket closed: {client.name} ({client.id})"
      clients.keepItIf(it != client)
      if client.name.len > 0:
        broadcast(Left(client.name))
        if pauseOnLeave:
          playing = false
          broadcast(State(playing, timestamp))
  else:
    await serveFile(req)

var server = newAsyncHttpServer()
waitFor server.serve(Port(9001), cb)
