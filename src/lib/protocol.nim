import json, patty
export json, patty

type
  Role* = enum
    user, janny, admin

  MediaItem* = object
    url*: string
    title*: string

variantp Event:
  Auth(name, password: string)
  Janny(jaName: string, state: bool)
  Joined(joName: string, role: Role)
  Left(leName: string)
  Renamed(oldName, newName: string)
  State(playing: bool, time: float)
  Message(user, text: string)
  Clients(clients: seq[string])
  Jannies(jannies: seq[string])
  PlaylistLoad(playlist: seq[MediaItem])
  PlaylistAdd(item: MediaItem)
  PlaylistPlay(index: int)
  PlaylistClear
  Success
  Error(reason: string)
  Null

proc unpack*(ev: string): Event =
  if ev.len == 0: return Null()
  parseJson(ev).to(Event)
