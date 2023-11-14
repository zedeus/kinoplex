import json, math, random

proc msToTime(time: float): JsonNode =
  let hours = floor(time / 60 / 60).int
  let minutes = floor(time / 60).int - hours * 60
  let seconds = floor(time).int - minutes * 60 - hours * 60 * 60
  let milliseconds = int((time - floor(time)) * 100)

  return %*{
    "hours": hours,
    "minutes": minutes,
    "seconds": seconds,
    "milliseconds": milliseconds
  }

proc timeToMs*(time: JsonNode): float =
  let hours = time["hours"].getInt(0)
  let minutes = time["minutes"].getInt(0)
  let seconds = time["seconds"].getInt(0)
  let milliseconds = time["milliseconds"].getInt(0)
  return float(hours * 60 * 60 + minutes * 60 + seconds) + milliseconds / 1000

proc cmd(function: string; params: JsonNode): JsonNode =
  %*{
    "jsonrpc": "2.0",
    "method": function,
    "params": params,
    "id": rand(10000)
  }

proc cmd(function: string): JsonNode =
  %*{
    "jsonrpc": "2.0",
    "method": function,
    "id": rand(10000)
  }

proc showMessage*(title: string; message: string; image="",
                  displaytime=5000): JsonNode =
  cmd("GUI.ShowNotification", %*{
    "title": title,
    "message": message,
    "image": image,
    "displaytime": displaytime
  })

proc playUrl*(url: string; time: float): JsonNode =
  cmd("Player.Open", %*{
    "item": {"file": "plugin://plugin.video.sendtokodi/?" & url},
    "options": {"resume": if time == 0: %false else: msToTime(time)}
  })

proc togglePlayer*(state: bool): JsonNode =
  cmd("Player.PlayPause", %*{
    "playerid": 1,
    "play": state
  })

proc stop*(): JsonNode =
  cmd("Player.Stop", %*{
    "playerid": 1
  })

proc seek*(time: float): JsonNode =
  cmd("Player.Seek", %*{
    "playerid": 1,
    "value": {"time": msToTime(time)}
  })

proc getTime*(): JsonNode =
  cmd("Player.GetProperties", %*{
    "playerid": 1,
    "properties": ["time"]
  })
