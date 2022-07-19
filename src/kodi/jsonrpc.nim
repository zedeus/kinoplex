import json

proc cmd(function: string; params: JsonNode): JsonNode =
  %*{
    "jsonrpc": "2.0",
    "method": function,
    "params": params,
    "id": 1
  }

proc cmd(function: string): JsonNode =
  %*{
    "jsonrpc": "2.0",
    "method": function,
    "id": 1
  }

proc showMessage*(title: string; description: string; image="",
                  displaytime=5000): JsonNode =
  cmd("GUI.ShowNotification", %*{
    "title": title,
    "description": description,
    "image": image,
    "displaytime": displaytime
  })

proc playUrl*(url: string; percentage: float): JsonNode =
  cmd("Player.Open", %*{
    "item": {"file": url},
    "options": {"resume": percentage}
  })

proc togglePlayer*(): JsonNode =
  cmd("Player.PlayPause", %*{
    "playerid": 0
  })

proc stop*(): JsonNode =
  cmd("Player.Stop", %*{
    "playerid": 0
  })

proc seek*(url: string; percentage: float): JsonNode =
  cmd("Player.Seek", %*{
    "playerid": 0,
    "value": {"percentage": percentage}
  })
