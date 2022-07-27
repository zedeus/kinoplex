import std/json
import protocol

when defined(js):
  import websockets
  export websockets
else:
  import std/asyncdispatch
  import ws
  export ws

type
  Client* = ref object of RootObj
    ws*: WebSocket
    name*: string
    role*: Role

    when defined(js):
      authCb: proc (ev: MessageEvent)
      eventCb: proc (ev: MessageEvent)

when defined(js):
  proc send*(client: Client, data: protocol.Event) =
    client.ws.send(cstring($(%data)))

  template authenticate*(client: Client, password: string, ev, body: untyped): untyped =
    client.authCb =
      proc (msg: MessageEvent) =
        let ev = unpack($msg.data)
        body

        match ev:
          Joined(_, _):
            client.ws.onMessage = client.eventCb
          _: discard

    client.ws.onMessage = client.authCb
    client.send(Auth(client.name, password))

  template poll*(client: Client, ev, body: untyped): untyped =
    client.eventCb =
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

  template poll*(client: Client, ev, body: untyped): untyped =
    proc cb(ev: Event) {.async.} =
      body

    while client.ws.readyState == Open:
      let ev = unpack(await client.ws.receiveStrPacket())
      await cb(ev)
