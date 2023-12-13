import malebolgia/lockers

var global = initLocker(new int)

lock global as local:
    var owner2 = local
    echo owner2[]
    #will arc do anything after end of this block?