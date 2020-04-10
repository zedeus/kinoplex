import strutils, json
export json

type
  Role* = enum
    user, janny, admin

  EventKind* = enum
    Null, Auth, State, Message,
    Clients, Joined, Left, Janny,
    PlaylistLoad, PlaylistAdd, PlaylistPlay, PlaylistClear

  Event* = object
    kind*: EventKind
    data*: JsonNode

proc pack*(kind: EventKind; data: JsonNode): string =
  $ord(kind) & ":" & $data

proc pack*(ev: Event): string =
  pack(ev.kind, ev.data)

proc unpack*(ev: string): Event =
  try:
    let parts = ev.split(":", maxSplit=1)
    Event(kind: EventKind(parseInt(parts[0])), data: parseJson(parts[1]))
  except:
    Event(kind: Null)

template state*(playing, time): string =
  State.pack(%*{"playing": playing, "time": time})
