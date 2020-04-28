import jsbind, dom

type Plyr* = ref object of JSObj
type PlyrSource* = ref object of JSObj

proc newPlyr*(e: Node): Plyr {.jsimportgWithName: "new Plyr".}
proc newSource*(src: jsstring): PlyrSource {.jsimportgWithName: "function(src){return {type:'video',title:'Kinoplex','sources':[{src:src}]}}".}

proc play*(p: Plyr) {.jsimport.}
proc pause*(p: Plyr) {.jsimport.}
proc togglePlay*(p: Plyr; status: bool) {.jsimport.}
proc destroy*(p: Plyr) {.jsimport.}

proc source*(p: Plyr): jsstring {.jsimportProp.}
proc `source=`*(p: Plyr; s: PlyrSource) {.jsimportProp.}

proc `currentTime`*(p: Plyr): float {.jsimportProp.}
proc `currentTime=`*(p: Plyr; t: float) {.jsimportProp.}
