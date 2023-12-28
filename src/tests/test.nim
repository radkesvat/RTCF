import chronos, chronos/timer, threading/channels


proc doo()=
    try:
        raise newException(CancelledError,"hi")
    except CatchableError as e:
        echo "catch"; raise e
    finally:
        echo "fin"

proc g()=
    try:
        doo()
    except :
        echo "g"
    finally:
        echo "gfin"
g()
        