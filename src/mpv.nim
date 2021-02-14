import asyncdispatch, osproc, net, json, random, strformat, strutils, os
export osproc

randomize()

when defined(windows):
  import asyncfile
  var fd = r"\\.\pipe\mpv-socket"
  var mpvPath = r"C:\mpv.exe"
else:
  import asyncnet
  var fd = &"/tmp/kinoplex{rand(99999)}.sock"
  var mpvPath = "mpv"

type
  Mpv* = ref object
    when defined(windows):
      sock*: AsyncFile
    else:
      sock*: AsyncSocket
    running*: bool
    process*: Process
    filename*: string
    index*: int
    playing*: bool
    time*: float

var mpvArgs = @[
  "--input-ipc-server=" & fd,
  "--no-terminal",
  "--force-window",
  "--keep-open",
  "--idle",
  "--hr-seek=yes",
  "--script=" & getAppDir() / "sync.lua"
]

proc safeAsync[T](fut: Future[T]) =
  fut.callback = (proc () = discard)

template recvLine*(mpv: Mpv): Future[string] =
  when defined(windows):
    player.sock.readLine()
  else:
    player.sock.recvLine()

template send(mpv: Mpv; text: string): Future[void] =
  when defined(windows):
    mpv.sock.write(text)
  else:
    mpv.sock.send(text)

template command(args) =
  safeAsync send(mpv, $(%*{"command": args}) & "\n")
  # echo $(%*{"command": args})

template command(args, id) =
  safeAsync send(mpv, $(%*{"command": args, "request_id": id}) & "\n")
  # echo $(%*{"command": args, "request_id": id})

proc loadFile*(mpv: Mpv; filename: string) =
  command ["loadfile", filename]

proc playlistAppend*(mpv: Mpv; filename: string) =
  command ["loadfile", filename, "append"]

proc playlistAppendPlay*(mpv: Mpv; filename: string) =
  command ["loadfile", filename, "append-play"]

proc playlistPlay*(mpv: Mpv; index: int) =
  command ["set_property", "playlist-pos", index]
  mpv.index = index
  mpv.time = 0

proc playlistMove*(mpv: Mpv; index1, index2: int) =
  command ["playlist-move", index1, index2]

proc playlistRemove*(mpv: Mpv; index: int) =
  command ["playlist-remove", index]

proc playlistClear*(mpv: Mpv) =
  command ["playlist-clear"]
  command ["playlist-remove", 0]

proc playlistPlayAndRemove*(mpv: Mpv; play, remove: int) {.async.} =
  mpv.time = 0
  await mpv.send $(%*{"command": ["set_property", "playlist-pos", play]}) & "\n"
  await mpv.send $(%*{"command": ["playlist-remove", remove]}) & "\n"

proc setPlaying*(mpv: Mpv; playing: bool) =
  mpv.playing = playing
  command ["set_property", "pause", not playing]

proc getTime*(mpv: Mpv) =
  command ["get_property", "playback-time"], 1

proc setTime*(mpv: Mpv; time: float) =
  if abs(mpv.time - time) < 1: return
  command ["set_property", "playback-time", time]

proc showText*(mpv: Mpv; text: string) =
  command ["script-message-to", "sync", "chat", text]

proc showEvent*(mpv: Mpv; text: string) =
  command ["script-message-to", "sync", "chat-osd-bad", text]

proc clearChat*(mpv: Mpv) =
  command ["script-message-to", "sync", "clear"]

proc close*(mpv: Mpv) =
  echo "Closing mpv socket"
  mpv.running = false
  terminate mpv.process
  close mpv.sock

proc startMpv*(): Future[Mpv] {.async.} =
  echo "Starting mpv"
  let mpv = Mpv(
    process: startProcess(mpvPath, args=mpvArgs, options={poUsePath, poParentStreams}),
    running: true
  )

  # wait for mpv to start
  await sleepAsync(500)

  try:
    when not defined(windows):
      mpv.sock = newAsyncSocket(AF_UNIX, SOCK_STREAM, IPPROTO_IP)
      await mpv.sock.connectUnix(fd)
      await sleepAsync(200)
    else:
      await sleepAsync(500)
      mpv.sock = openAsync(fd, fmReadWrite)

    command ["observe_property", 1, "playlist-pos"]
  except:
    echo "Failed to connect to mpv socket"
    terminate mpv.process
    close mpv.sock
    return

  return mpv

proc restart*(mpv: Mpv) {.async.} =
  close mpv
  mpv.running = true
  let newMpv = await startMpv()
  mpv.process = newMpv.process
  mpv.sock = newMpv.sock
