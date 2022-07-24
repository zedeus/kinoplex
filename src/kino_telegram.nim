import std/[asyncdispatch, options, json, strutils, strformat, tables]
import ws, telebot
import questionable
import ./protocol
import telegram/config

type
  Client = object
    user: User
    ws: WebSocket
  
  Server = object
    clients: Table[int, Client]
    host: string
    playlist: seq[string]

let cfg = getConfig()
  
var
  server: Server
  bot: Telebot

proc getClient(server: Server, user: User): ?Client =
  if server.clients.hasKey(user.id):
    return some server.clients[user.id]
  
proc send(client: ?Client, data: Event) =
  if fut =? client.?ws.?send($(%data)):
    asyncCheck fut

proc showEvent(client: Client, text: string) {.async.} =
  discard await bot.sendMessage(client.user.id, text)

proc join(client: Client): Future[bool] {.async.} =
  echo "Joining.."
  await client.ws.send($(%Auth(client.user.username.get, "")))

  let resp = unpack(await client.ws.receiveStrPacket())
  match resp:
    Joined(newName, newRole):
      await client.showEvent("Welcome to the kinoplex!")
    Error(reason):
      await client.showEvent("bridge failed to join: " & reason)
      result = true
    _: discard

proc handleServer(client: Client) {.async.} =
  if await client.join(): return
  client.ws.setupPings(5)
  while client.ws.readyState == Open:
    let event = unpack(await client.ws.receiveStrPacket())
    match event:
      Message(name, text):
        discard await bot.sendMessage(client.user.id, name & ": " & text)
      Clients(names):
        await client.showEvent("Users: " & names.join(", "))
      Joined(name, role):
        await client.showEvent(&"{name} joined as {role}")
      Left(name):
        await client.showEvent(name & " left")
      Jannies(jannies):
        if jannies.len < 1:
          await client.showEvent("There are currently no jannies")
        else:
          await client.showEvent("Jannies: " & jannies.join(", "))
      PlaylistAdd(url):
        server.playlist.add url
      PlaylistPlay(index):
        await client.showEvent("Playing " & server.playlist[index])
      PlaylistClear:
        server.playlist.setLen(0)
        await client.showEvent("Playlist cleared")
      Error(reason):
        await client.showEvent(reason)
      Null: discard
      Auth: discard
      Success: discard
      _: discard
                  
  close client.ws
  server.clients.del(client.user.id)

proc validUrl(url: string; acceptFile=false): bool =
  url.len > 0 and "\n" notin url and (acceptFile or "http" in url)

template handlerizerKinoplex(body: untyped): untyped =
  proc cb(bot: Telebot, c: Command): Future[bool] {.gcsafe async.} =
    if c.message.fromUser.isNone: return

    let
      client {.inject.} = server.getClient(!c.message.fromUser)
      message {.inject.} = c.message
    body

  result = cb

proc usersHandler(bot: Telebot): CommandCallback =
  handlerizerKinoplex:
    client.send(Clients(@[]))

proc janniesHandler(bot: Telebot): CommandCallback =
  handlerizerKinoplex:
    client.send(Jannies(@[]))

proc addHandler(bot: Telebot): CommandCallback =
  handlerizerKinoplex:
    if client.isNone: return
    without parts =? message.text.?split(" ", maxSplit=1): return

    if parts.len == 1 or not validUrl(parts[1]):
      await client.get.showEvent("No url specified")
    else:
      client.send(PlaylistAdd(parts[1]))

proc startHandler(bot: Telebot, c: Command): Future[bool] {.gcsafe async.} =
  without user =? c.message.fromUser: return
  
  let
    chat = c.message.chat
    ws = await newWebSocket(server.host)
    client = Client(user: user, ws: ws)
    
  server.clients[user.id] = client
  yield client.handleServer()
  
  return true

proc stopHandler(bot: Telebot, c: Command): Future[bool] {.gcsafe async.} =
  if server.clients.len < 1: return
  without user =? c.message.fromUser: return

  discard await bot.sendMessage(user.id, "Leaving")

  without client =? server.getClient(user): return
  client.ws.close
  
  if clientId =? client.user.id:
    server.clients.del(clientId)

proc updateHandler(bot: Telebot, u: Update): Future[bool] {.gcsafe async.} =
  if server.clients.len == 0: return
  without message =? u.message: return

  without text =? message.text: return
  if text[0] == '/': return
  
  without user =? message.fromUser: return
  let
    username = user.username |? user.firstName
    client = server.getClient(user)

  client.send(Message(username, text))
  return true

proc main() {.async.} =
  bot = newTeleBot(cfg.token)
  
  server = Server(host: (if cfg.useTls: "wss://" else: "ws://") & cfg.address)
  
  bot.onUpdate(updateHandler)
  bot.onCommand("join", startHandler)
  bot.onCommand("leave", stopHandler)
  bot.onCommand("users", usersHandler(bot))
  bot.onCommand("jannies", janniesHandler(bot))
  bot.onCommand("add", addHandler(bot))
  bot.poll(timeout = 300)


waitFor main()
