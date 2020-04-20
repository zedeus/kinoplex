include karax / prelude
import plyr

var player*: Plyr
  
proc postRender() =
  player = newPlyr()
  
proc createDom(): VNode =
  result = buildHtml(tdiv(align="center")):
    h1(text "Kinoweb")
    br()
    video(id="player", playsinline="", controls="")
    
setRenderer createDom, "ROOT", postRender
