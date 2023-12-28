
import std/[random]
from globals import nil
import beforegfw,aftergfw

randomize()
globals.init()


if globals.mode == globals.RunMode.iran:
    beforeGFW.start()
# else:
#     afterGFW.start()



