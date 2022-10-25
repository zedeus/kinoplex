import std/[os, asyncdispatch, asynchttpserver, sequtils, strutils, strformat,
            strtabs]
import ws
import protocol, server/config

type
  Client = ref object
    id: int
    name: string
    role: Role
    ws: WebSocket

let cfg = getConfig()

var
  clients: seq[Client]
  playing: bool
  playlist: seq[string]
  playlistIndex = 0
  globalId = 0
  timestamp = 0.0
  httpCache = newStringTable()

template send(client, msg) =
  try:
    if client.ws.readyState == Open:
      asyncCheck client.ws.send($(%msg))
  except WebSocketError:
    discard

proc shorten(text: string; limit: int): string =
  text[0..min(limit, text.high)]

proc broadcast(msg: Event; skip=(-1)) =
  for c in clients:
    if c.id == skip: continue
    c.send(msg)

proc sendEvent(client: Client, msg: string) =
  client.send(Message("server", msg))

proc broadcastEvent(msg: string) =
  broadcast(Message("server", msg))

proc setName(client: Client, name: string) =
  let shortName = name.shorten(24)
  
  if shortName.len == 0:
    client.send(Error("name empty"))
    return 
  
  if shortName == "server":
    client.send(Error("spoofing the server is not allowed"))
    return
  
  if clients.anyIt(it.name == shortName):
    client.send(Error("name already taken"))
    return

  client.name = shortName

proc authorize(client: Client; name, pass: string) {.async.} =
  if pass.len > 0 and pass == cfg.adminPassword:
    if not clients.anyIt(it.role == admin):
      client.role = admin

  client.setName(name)
  if client.name.len == 0: return
  
  client.send(Joined(client.name, client.role))
  client.id = globalId
  inc globalId
  clients.add client
  broadcast(Joined(client.name, client.role), skip=client.id)
  echo &"New client: {client.name} ({client.id})"

  client.send(Clients(clients.mapIt(it.name)))
  client.send(Jannies(clients.filterIt(it.role == janny).mapIt(it.name)))
  
  if playlist.len > 0:
    client.send(PlaylistLoad(playlist))
    client.send(PlaylistPlay(playlistIndex))
  client.send(State(playing, timestamp))

proc handle(client: Client; ev: Event) {.async.} =
  # if ev.kind != EventKind.Auth:
  #   echo "(", client.name, ") ", ev

  template checkPermission(minRole) =
    if client.role < minRole:
      client.sendEvent("You don't have permission")
      return

  match ev:
    Auth(name, pass):
      asyncCheck client.authorize(name, pass)
    Message(_, text):
      broadcast(Message(client.name, text.shorten(280)), skip=client.id)
    Renamed(oldName, newName):
      client.setName(newName)
      
      if client.name != oldName:
        broadcastEvent(&"'{oldName}' changed their name to '{client.name}'")
        broadcast(Renamed(oldName, client.name))
    Clients:
      client.send(Clients(clients.mapIt(it.name)))
    Jannies:
      client.send(Jannies(clients.filterIt(it.role == janny).mapIt(it.name)))
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
        client.sendEvent("Invalid url")
      else:
        playlist.add url
        broadcast(PlaylistAdd(url))
        broadcastEvent(&"{client.name} added {url}")
        if playlist.len == 1:
          broadcast(PlaylistPlay(0))
    PlaylistPlay(index):
      checkPermission(janny)
      if index > playlist.high:
        client.sendEvent("Index too high")
      elif index < 0:
        client.sendEvent("Index too low")
      else:
        playlistIndex = index
        if cfg.pauseOnChange:
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
          client.send(Error(c.name & " is already a janny"))
          return
        elif state and c.role == user:
          c.role = janny
          broadcastEvent(c.name & " became a janny")
        elif not state and c.role == janny:
          c.role = user
          broadcastEvent(c.name & " is no longer a janny")
        broadcast(Janny(c.name, state))
      
      if not found:
        client.send(Error("Invalid user"))
    _: echo "unknown: ", ev

proc serveFile(req: Request) {.async.} =
  var
    file: string
    content: string
    code = Http200

  let
    root = cfg.staticDir
    index = root / "client.html"
    path = req.url.path.relativePath(cfg.basePath)
    filePath = root / path
    error404 = "File not found (404)"

  if dirExists(root):
    if req.url.path == cfg.basePath:
      if fileExists(index):
        file = index

    if fileExists(filePath):
      file = filePath

  if file.len > 0:
    if file notin httpCache:
      httpCache[file] = file.readFile
    content = httpCache[file]
  else:
    content = error404
    code = Http404

  await req.respond(code, content)

proc cb(req: Request) {.async, gcsafe.} =
  if req.url.path.relativePath(cfg.basePath) == "ws":
    var client = Client()
    try:
      client.ws = await newWebSocket(req)
      while client.ws.readyState == Open:
        let msg = await client.ws.receiveStrPacket()
        if msg.len > 0:
          await client.handle(unpack msg)
    except WebSocketError:
      if client notin clients: return
      echo &"socket closed: {client.name} ({client.id})"
      clients.keepItIf(it != client)
      if client.name.len > 0:
        broadcast(Left(client.name))
        if cfg.pauseOnLeave or client.role == admin:
          playing = false
          broadcast(State(playing, timestamp))
  else:
    await serveFile(req)

echo "Listening at ws://localhost:", cfg.port, cfg.basePath / "ws"
var server = newAsyncHttpServer()
waitFor server.serve(Port(cfg.port), cb)
