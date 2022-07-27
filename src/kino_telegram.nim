import std/[asyncdispatch, options, json, strformat, tables]
import std/strutils except escape
from std/xmltree import escape
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
    index: int

let cfg = getConfig()
  
var
  server: Server
  bot: Telebot

proc safeAsync[T](fut: Future[T]) = fut.callback = (proc () = discard)

proc getClient(server: Server, user: User): ?Client =
  if server.clients.hasKey(user.id):
    return some server.clients[user.id]

proc send(client: Client, data: Event) =
  safeAsync client.ws.send($(%data))

proc sendMsg(bot: TeleBot, client: Client, message: string) {.async.} =
  discard await bot.sendMessage(client.user.id, message, "HTML")

proc escapeHtml(text: string): string =
  result = escape(text).replace("&apos;", "'")

template showEvent(text: string): untyped =
  await bot.sendMsg(client, "<i>" & text.escapeHtml & "</i>")

template showMessage(name, text: string) =
  await bot.sendMsg(client, "<b>" & name.escapeHtml & "</b>: " & text.escapeHtml)

proc join(client: Client): Future[bool] {.async.} =
  await client.ws.send($(%Auth(client.user.username.get, "")))

  let resp = unpack(await client.ws.receiveStrPacket())
  match resp:
    Joined(newName, newRole):
      showEvent("Welcome to the kinoplex!")
    Error(reason):
      showEvent("Joining failed:: " & reason)
      result = true
    _: discard

proc handleServer(client: Client) {.async.} =
  if await client.join(): return
  client.ws.setupPings(5)
  while client.ws.readyState == Open:
    let event = unpack(await client.ws.receiveStrPacket())
    if event.kind notin {EventKind.State, EventKind.Null}:
      echo "event: ", event.kind

    match event:
      Message(name, text):
        showMessage(name, text)
      Clients(names):
        showEvent("Users: " & names.join(", "))
      Joined(name, role):
        showEvent(&"{name} joined as {role}")
      Left(name):
        showEvent(name & " left")
      Janny(jannyName, isJanny):
        if client.role != admin:
          client.role = if isJanny and client.name == jannyName: janny
                        else: user
      Jannies(jannies):
        if jannies.len < 1:
          showEvent("There are currently no jannies")
        else:
          showEvent("Jannies: " & jannies.join(", "))
      PlaylistAdd(url):
        server.playlist.add url
      PlaylistLoad(urls):
        server.playlist = urls
      PlaylistPlay(index):
        server.index = index
        showEvent("Playing " & server.playlist[index])
      PlaylistClear:
        server.playlist.setLen(0)
        server.index = 0
        showEvent("Playlist cleared")
      Error(reason):
        echo "error: ", reason
        showEvent(reason)
      Null: discard
      Auth: discard
      Success: discard
      _: discard

  close client.ws
  server.clients.del(client.user.id)

proc validUrl(url: string; acceptFile=false): bool =
  url.len > 0 and "\n" notin url and (acceptFile or "http" in url)

template kinoHandler(name, body: untyped): untyped =
  proc name(bot: Telebot, c: Command): Future[bool] {.async, gcsafe.} =
    if c.message.fromUser.isNone: return

    let
      maybeClient = server.getClient(!c.message.fromUser)
      maybeText = c.message.text
    if maybeClient.isNone or maybeText.isNone: return

    let
      client {.inject.} = maybeClient.get
      parts {.inject, used.} = maybeText.get.split(" ", maxSplit=1)

    body

kinoHandler users:
  client.send(Clients(@[]))

kinoHandler jannies:
  client.send(Jannies(@[]))

kinoHandler addUrl:
  if parts.len == 1 or not validUrl(parts[1]):
    showEvent("No url specified")
  else:
    client.send(PlaylistAdd(parts[1]))

kinoHandler next:
  if client.role < janny:
    showEvent("Insufficient role")
  elif server.index + 1 < server.playlist.len:
    inc server.index
    client.send(PlaylistPlay(server.index))
    showEvent("Playing " & server.playlist[server.index])
  else:
    showEvent("No more videos left")

kinoHandler prev:
  if client.role < janny:
    showEvent("Insufficient role")
  elif server.index > 0:
    dec server.index
    client.send(PlaylistPlay(server.index))
    showEvent("Playing " & server.playlist[server.index])
  else:
    showEvent("Already at beginning of playlist")

kinoHandler playlist:
  var message = "Playlist:"
  for i, url in server.playlist:
    message &= "\n$1 $2" % [$i, url]
  showEvent(message)

kinoHandler leave:
  if server.clients.len == 0: return
  showEvent("Leaving")
  close client.ws

  if clientId =? client.user.id:
     server.clients.del(clientId)

proc joinHandler(bot: Telebot, c: Command): Future[bool] {.async, gcsafe.} =
  without user =? c.message.fromUser: return

  let client = Client(user: user)

  try:
    client.ws = await newWebSocket(server.host)
    server.clients[user.id] = client
    safeAsync client.handleServer()
  except OSError, WebSocketError:
    showEvent("Connection to kinoplex failed")

  return true

proc updateHandler(bot: Telebot, u: Update): Future[bool] {.async, gcsafe.} =
  if server.clients.len == 0: return
  without message =? u.message: return

  without text =? message.text: return
  if text[0] == '/': return
  
  without user =? message.fromUser: return
  let username = user.username |? user.firstName

  without client =? server.getClient(user): return
  client.send(Message(username, text))
  
  return true

proc main() {.async.} =
  bot = newTeleBot(cfg.token)
  
  server = Server(host: (if cfg.useTls: "wss://" else: "ws://") & cfg.address)
  
  bot.onUpdate(updateHandler)
  bot.onCommand("join", joinHandler)
  bot.onCommand("leave", leave)
  bot.onCommand("users", users)
  bot.onCommand("jannies", jannies)
  bot.onCommand("add", addUrl)
  bot.onCommand("next", next)
  bot.onCommand("prev", prev)
  bot.onCommand("playlist", playlist)
  bot.poll(timeout = 300)


waitFor main()
