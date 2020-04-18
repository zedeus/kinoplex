# Package

version       = "0.1.0"
author        = "Zed"
description   = "Server and client for syncing mpv playback"
license       = "AGPLv3"
srcDir        = "src"
bin           = @["client", "server"]


# Dependencies

requires "nim >= 1.2.0", "ws", "jswebsockets", "karax", "patty"

# Tasks

import strformat
task windows, "Build static Windows binary":
  let overrides = "--dynlibOverride:\"(libssl-1_1-x64|libcrypto-1_1-x64).dll\""
  let fallback = "-L/usr/x86_64-w64-mingw32/lib -lssl -lcrypto -lws2_32 -lcrypt32"
  var (config, exit) = gorgeEx("x86_64-w64-mingw32-pkg-config --static --libs openssl")
  if exit != 1:
    echo "mingw pkg-config not installed, trying fallback"
    config = fallback
  let libs = &"--dynlibOverride:ssl {overrides} --passL:\"-Wl,-Bstatic {config} -lssp\""
  exec &"nim c -d:release --opt:size -d:ssl -d:mingw --cpu:amd64 {libs} -o=client.exe src/client.nim"

task webclient, "Compile the web client JS":
  exec "nim --skipParentCfg js -o:static/sync.js src/sync.nim"
