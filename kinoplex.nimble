# Package

version       = "0.1.0"
author        = "Zed"
description   = "Server and client for syncing media playback"
license       = "AGPLv3"
srcDir        = "src"
bin           = @["kino_server", "kino_mpv"]


# Dependencies

requires "nim >= 1.4.8"
requires "patty#4bed5b8"
requires "karax#fa4a2dc"
requires "https://github.com/tandy-1000/websockets#fe466ab"
requires "ws" # must be version-less because nimble is dumb

# Tasks

task webclient, "Build the web client.":
  exec "nimble js -d:danger --experimental:dotOperators -o:static/client.js src/kino_web.nim"

import strformat
task windows, "  Build static Windows binary":
  let overrides = "--dynlibOverride:\"(libssl-1_1-x64|libcrypto-1_1-x64).dll\""
  let fallback = "-L/usr/x86_64-w64-mingw32/lib -lssl -lcrypto -lws2_32 -lcrypt32"
  var (config, exit) = gorgeEx("x86_64-w64-mingw32-pkg-config --static --libs openssl")
  if exit != 1:
    echo "mingw pkg-config not installed, trying fallback"
    config = fallback
  let libs = &"--dynlibOverride:ssl {overrides} --passL:\"-Wl,-Bstatic {config} -lssp\""
  exec &"nim c -d:release --opt:size -d:ssl -d:mingw --cpu:amd64 {libs} -o=client.exe src/kino_mpv.nim"
