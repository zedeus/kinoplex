--define:ssl
--gc:orc
--threads:off
warning("GcUnsafe2", off)
# begin Nimble config (version 2)
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config
