import std/[asyncdispatch, options, json, sequtils, strutils, strformat]
import ws, telebot
import ./protocol
import telegram/config

type
  Client = object
    user: User
    ws: WebSocket
  
  Server = object
    clients: seq[Client]
    host: string

let cfg = getConfig()
  
var
  server: Server
  bot: Telebot

proc send(client: Client, data: Event) =
  asyncCheck client.ws.send($(%data))

proc showEvent(client: Client, text: string) {.async.} =
  discard await bot.sendMessage(client.user.id, text)

proc join(client: Client): Future[bool] {.async.} =
  echo "Joining.."
  await client.ws.send($(%Auth(client.user.username.get, "")))

  let resp = unpack(await client.ws.receiveStrPacket())
  match resp:
    Joined(newName, newRole):
      await client.showEvent("Welcome to kinoplex!")
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
      Error(reason):
        await client.showEvent(reason)
      Null: discard
      Auth: discard
      Success: discard
      _: discard
                  
  #close client.ws
  #server.clients.keepItIf(it.user.id != client.user.id)

proc startHandler(bot: Telebot, c: Command): Future[bool] {.gcsafe async.} =
  if c.message.fromUser.isNone: return
  
  let
    user = c.message.fromUser.get
    chat = c.message.chat
    ws = await newWebSocket(server.host)
    client = Client(user: user, ws: ws)
    
  server.clients.add client
  yield client.handleServer()
  
  return true

proc stopHandler(bot: Telebot, c: Command): Future[bool] {.gcsafe async.} =
  if server.clients.len < 1: return
  if c.message.fromUser.isNone: return

  let
    user = c.message.fromUser.get
    idx = server.clients.mapIt(it.user.id).find(user.id)
    
  if idx < 0: return
  discard await bot.sendMessage(user.id, "Leaving")
  close server.clients[idx].ws
  server.clients.delete(idx)
  
proc updateHandler(bot: Telebot, u: Update): Future[bool] {.gcsafe async.} =
  if server.clients.len < 1: return
  if u.message.isNone: return
  
  let message = u.message.get()
  if message.text.isNone: return
  if message.fromUser.isNone: return

  let text = message.text.get
  if text[0] == '/': return
  
  let
    user = message.fromUser.get()
    username =
      if user.username.isSome:
        '@' & user.username.get()
      else:
        user.firstName

  let idx = server.clients.mapIt(it.user.id).find(user.id)
  server.clients[idx].send(Message(username, message.text.get()))
    
  return true

proc main() {.async.} =
  bot = newTeleBot(cfg.token)
  
  server = Server(host: (if cfg.useTls: "wss://" else: "ws://") & cfg.address)
  
  bot.onUpdate(updateHandler)
  bot.onCommand("start", startHandler)
  bot.onCommand("stop", stopHandler)
  bot.poll(timeout = 300)


waitFor main()
