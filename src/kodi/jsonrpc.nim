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

proc togglePlayer*(state: bool): JsonNode =
  cmd("Player.PlayPause", %*{
    "playerid": 0,
    "toggle": state
  })

proc stop*(): JsonNode =
  cmd("Player.Stop", %*{
    "playerid": 0
  })

proc seek*(percentage: float): JsonNode =
  cmd("Player.Seek", %*{
    "playerid": 0,
    "value": {"percentage": percentage}
  })

proc getTime*(): JsonNode =
  cmd("Player.GetProperties", %*{
    "playerid": 0,
    "properties": ["percentage"]
  })
