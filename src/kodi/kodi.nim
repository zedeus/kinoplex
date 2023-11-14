import std/[asyncdispatch, json, strutils]
import ws

type
  Kodi* = ref object
    ws*: WebSocket
    connected*: bool
    playing*: bool
    time*: float

proc sendCmd*(client: Kodi; cmd: JsonNode) =
  if cmd["method"].getStr != "Player.GetProperties":
    echo "command: ", cmd
  asyncCheck client.ws.send($cmd)

proc connect*(host: string): Future[Kodi] {.async.} =
  result = Kodi(
    ws: await newWebSocket("ws://" & host & "/jsonrpc"),
    connected: true
  )
