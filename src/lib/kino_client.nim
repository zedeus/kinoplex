import std/[json, uri]
import protocol

when defined(js):
  import websockets
  export websockets
else:
  import std/asyncdispatch
  import ws
  export ws

type
  Msg* = object
    name*: string
    text*: string

  Server* = object of RootObj
    host*: string
    users*, jannies*: seq[string]
    messages*: seq[Msg]
    playlist*: seq[string]
    playing*: bool
    index*: int
    time*: float

  Client* = ref object of RootObj
    ws*: WebSocket
    name*: string
    role*: Role

when defined(js):
  proc send*(client: Client, data: protocol.Event) =
    client.ws.send(cstring($(%data)))

  template authenticate*(client: Client, password: string, ev, body: untyped): untyped =
    client.ws.onMessage =
      proc (msg: MessageEvent) =
        let ev = unpack($msg.data)
        body

    client.send(Auth(client.name, password))

  template poll*(client: Client, ev, body: untyped): untyped =
    client.ws.onMessage =
      proc (msg: MessageEvent) =
        let ev = unpack($msg.data)
        body

else:
  proc send*(client: Client, data: Event): Future[void] =
    client.ws.send($(%data))

  template receive*(client: Client, ev, body: untyped): untyped =
    proc cb(ev: Event) {.async.} =
      body

    let ev = unpack(await client.ws.receiveStrPacket())
    await cb(ev)

  template authenticate*(client: Client, password: string, ev, body: untyped): untyped =
    await client.send(Auth(client.name, password))
    
    client.receive(resp):
      body

  template poll*(client: Client, ev, body: untyped): untyped =
    proc cb(ev: Event) {.async.} =
      body

    while client.ws.readyState == Open:
      let ev = unpack(await client.ws.receiveStrPacket())
      await cb(ev)

proc recentMsgs*(server: Server; count: int): seq[Msg] =
  let startIndex = max(server.messages.len - count, 0)
  return server.messages[startIndex .. ^1]

proc getServerUri*(useTls: bool; host: string; path=""): string =
  result = $(Uri(
    scheme: if useTls: "wss" else: "ws",
    hostname: host,
    path: path
  ) / "ws")
