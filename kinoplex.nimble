# Package

version       = "0.1.0"
author        = "Zed"
description   = "Server and client for syncing mpv playback"
license       = "AGPLv3"
srcDir        = "src"
bin           = @["client", "server"]



# Dependencies

requires "nim >= 1.0", "ws", "msgpack4nim", "patty"
