import std/[asyncdispatch, json, strutils]
import ws
import jsonrpc

type
  Kodi* = ref object
    ws*: WebSocket
    connected*: bool
    filename*: string
    playing*: bool
    time*: float

proc sendCmd*(client: Kodi; cmd: JsonNode) =
  asyncCheck client.ws.send($cmd)

proc connect*(host: string): Future[Kodi] {.async.} =
  result = Kodi(
    ws: await newWebSocket("ws://" & host & "/jsonrpc"),
    connected: true
  )
