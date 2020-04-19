import jsbind

type Plyr* = ref object of JSObj

proc newPlyr*(): Plyr {.jsimportgWithName: "function(){return new Plyr('#player')}".}
proc play*(p: Plyr) {.jsimport.}
proc pause*(p: Plyr) {.jsimport.}
proc togglePlay*(p: Plyr, status: bool) {.jsimport.}

proc `source=`*(p: Plyr, src: cstring) {.jsimportProp.}
proc source*(p: Plyr): jsstring {.jsimportProp.}

proc `currentTime=`*(p: Plyr, t: float) {.jsimportProp.}
proc `currentTime`*(p: Plyr): float {.jsimportProp.}
