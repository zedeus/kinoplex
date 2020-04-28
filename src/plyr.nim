import dom

type
  Plyr* {.importc.} = ref object
    currentTime*: float

proc newPlyr*(e: Node): Plyr {.importcpp: "new Plyr(#)".}
proc togglePlay*(p: Plyr; status: bool) {.importcpp.}
proc `source=`*(p: Plyr; src: cstring) {.importcpp: "#.source = {type:'video',title:'Kinoplex','sources':[{src:@}]}".}
