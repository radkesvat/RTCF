
import std/[random]
from globals import nil
import beforeGFW,afterGFW

randomize()
globals.init()


if globals.mode == globals.RunMode.iran:
    beforeGFW.start()
# else:
#     afterGFW.start()



