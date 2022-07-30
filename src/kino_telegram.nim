import std/[asyncdispatch, options, json, strformat, tables]
import std/strutils except escape
from std/xmltree import escape
import telebot
import questionable
import lib/[protocol, kino_client, utils]
import telegram/config

type
  TgClient = ref object of Client
    user: User
  
  TgServer = object of Server
    clients: Table[int, TgClient]

let cfg = getConfig()

# threadvar silences nimsuggest's gc warnings
var
  server {.threadvar.}: TgServer
  bot {.threadvar.}: Telebot

template sendEvent(client: TgClient, data: Event) =
  safeAsync client.send(data)

proc getClient(server: TgServer, user: User): ?TgClient =
  if user.id in server.clients:
    return some server.clients[user.id]

proc sendMsg(bot: TeleBot, client: TgClient, message: string) {.async.} =
  discard await bot.sendMessage(client.user.id, message, "HTML")

proc escapeHtml(text: string): string =
  result = escape(text).replace("&apos;", "'")

template showEvent(text: string): untyped =
  await bot.sendMsg(client, "<i>" & text.escapeHtml & "</i>")

template showMessage(name, text: string) =
  await bot.sendMsg(client, "<b>" & name.escapeHtml & "</b>: " & text.escapeHtml)

proc join(client: TgClient): Future[bool] {.async.} =
  var error: bool
  client.authenticate("", resp):
    match resp:
      Joined(newName, newRole):
        client.name = newName
        client.role = newRole
        showEvent("Welcome to the kinoplex!")
      Error(reason):
        showEvent("Joining failed: " & reason)
        error = true
      _: discard

  return error

proc handleServer(client: TgClient) {.async.} =
  if await client.join(): return
  client.ws.setupPings(5)

  client.poll(event):
    if event.kind notin {EventKind.State, EventKind.Null}:
      echo "event: ", event.kind

    match event:
      Message(name, text):
        if name == "server":
          showEvent(text)
        else:
          showMessage(name, text)
      Clients(names):
        showEvent("Users: " & names.join(", "))
      Joined(name, role):
        showEvent(&"{name} joined as {role}")
      Left(name):
        showEvent(name & " left")
      Renamed(oldName, newName):
        if oldName == client.name:
          client.name = newName
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
        echo "Error: ", reason
        showEvent("Error: " & reason)
      Null: discard
      Auth: discard
      Success: discard
      _: discard

  close client.ws
  server.clients.del(client.user.id)

template kinoHandler(name, body: untyped): untyped =
  proc name(bot: Telebot, c: Command): Future[bool] {.async.} =
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
  client.sendEvent(Clients(@[]))

kinoHandler jannies:
  client.sendEvent(Jannies(@[]))

kinoHandler addUrl:
  if parts.len == 1 or not validUrl(parts[1]):
    showEvent("No url specified")
  else:
    client.sendEvent(PlaylistAdd(parts[1]))

kinoHandler next:
  if client.role < janny:
    showEvent("Insufficient role")
  elif server.index + 1 < server.playlist.len:
    inc server.index
    client.sendEvent(PlaylistPlay(server.index))
    showEvent("Playing " & server.playlist[server.index])
  else:
    showEvent("No more videos left")

kinoHandler prev:
  if client.role < janny:
    showEvent("Insufficient role")
  elif server.index > 0:
    dec server.index
    client.sendEvent(PlaylistPlay(server.index))
    showEvent("Playing " & server.playlist[server.index])
  else:
    showEvent("Already at beginning of playlist")

kinoHandler playlist:
  var message = "Playlist:"
  for i, url in server.playlist:
    message &= "\n$1 $2" % [$i, url]
  showEvent(message)

kinoHandler rename:
  if parts.len == 1:
    showEvent("No name specified")
  else:
    client.sendEvent(Renamed(client.name, parts[1]))

kinoHandler leave:
  if server.clients.len == 0: return
  showEvent("Leaving")
  close client.ws

  if clientId =? client.user.id:
     server.clients.del(clientId)

proc joinHandler(bot: Telebot, c: Command): Future[bool] {.async.} =
  without user =? c.message.fromUser: return

  let client = TgClient(user: user, name: user.username |? user.firstName)

  if user.id in server.clients:
    showEvent("Already connected")
    return

  try:
    client.ws = await newWebSocket(server.host)
    server.clients[user.id] = client
    safeAsync client.handleServer()
  except OSError, WebSocketError:
    showEvent("Connection to kinoplex failed")

  return true

proc updateHandler(bot: Telebot, u: Update): Future[bool] {.async.} =
  if server.clients.len == 0: return
  without message =? u.message: return

  without text =? message.text: return
  if text[0] == '/': return
  
  without user =? message.fromUser: return
  let username = user.username |? user.firstName

  without client =? server.getClient(user): return
  client.sendEvent(Message(username, text))
  
  return true

proc main() {.async.} =
  bot = newTeleBot(cfg.token)
  
  server = TgServer(host: getServerUri(cfg.useTls, cfg.address))
  
  bot.onUpdate(updateHandler)
  bot.onCommand("join", joinHandler)
  bot.onCommand("leave", leave)
  bot.onCommand("rename", rename)
  bot.onCommand("users", users)
  bot.onCommand("jannies", jannies)
  bot.onCommand("add", addUrl)
  bot.onCommand("next", next)
  bot.onCommand("prev", prev)
  bot.onCommand("playlist", playlist)

  bot.poll(timeout = 300)


waitFor main()
