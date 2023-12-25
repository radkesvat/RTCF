
import chronos
import std/[random, exitprocs]
from globals import nil
import beforeGFW,afterGFW

randomize()
globals.init()


if globals.mode == globals.RunMode.iran:
    asyncSpawn beforeGFW.start()
else:
    asyncSpawn afterGFW.start()


runForever()
