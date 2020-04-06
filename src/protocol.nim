import strutils

type
  EventKind* = enum
    Auth, State, Seek, Message,
    Clients, Joined, Left, Admin,
    PlaylistLoad, PlaylistAdd, PlaylistPlay, PlaylistClear

  Event* = object
    kind*: EventKind
    data*: string

proc pack*(kind: EventKind; data: string): string =
  $ord(kind) & ":" & data

proc pack*(ev: Event): string =
  pack(ev.kind, ev.data)

proc unpack*(ev: string): Event =
  let parts = ev.split(":", maxSplit=1)
  Event(kind: EventKind(parseInt(parts[0])), data: parts[1])
