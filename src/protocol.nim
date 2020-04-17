import msgpack4nim, patty
export msgpack4nim, patty

type
  Role* = enum
    user, janny, admin

variantp Event:
  Auth(name: string, password: string)
  Janny(jaName: string, state: bool)
  Joined(joName: string, role: Role)
  Left(leName: string)
  State(playing: bool, time: float)
  Message(text: string)
  Clients(clients: seq[string])
  PlaylistLoad(urls: seq[string])
  PlaylistAdd(url: string)
  PlaylistPlay(index: int)
  PlaylistClear
  Success
  Error(reason: string)
  Null

proc unpack*(ev: string): Event =
  if ev.len == 0: return Null()
  ev.unpack(result)
