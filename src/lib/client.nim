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
  proc send*(client: Client, data: protocol.Event) =
    client.ws.send(cstring($(%data)))

  template poll*(client: Client, ev, body: untyped): untyped =
    client.ws.onMessage =
      proc(msg: MessageEvent) =
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
    while client.ws.readyState == Open:
      client.receive(ev): body
  
