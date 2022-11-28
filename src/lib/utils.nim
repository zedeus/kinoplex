import std/strutils

when not defined(js):
  import std/asyncdispatch
  proc safeAsync*[T](fut: Future[T]) = fut.callback = (proc () = discard)
  
proc validUrl*(url: string; acceptFile=false): bool =
  url.len > 0 and "\n" notin url and (acceptFile or "http" in url)
