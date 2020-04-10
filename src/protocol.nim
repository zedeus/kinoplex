import strutils

type
  Role* = enum
    user, janny, admin

  EventKind* = enum
    Null, Auth, Playing, Seek, Message,
    Clients, Joined, Left, Janny,
    PlaylistLoad, PlaylistAdd, PlaylistPlay, PlaylistClear

  Event* = object
    kind*: EventKind
    data*: string

proc pack*(kind: EventKind; data: string): string =
  $ord(kind) & ":" & data

proc pack*(ev: Event): string =
  pack(ev.kind, ev.data)

proc unpack*(ev: string): Event =
  try:
    let parts = ev.split(":", maxSplit=1)
    Event(kind: EventKind(parseInt(parts[0])), data: parts[1])
  except:
    Event(kind: Null)
