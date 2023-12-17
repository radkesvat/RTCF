import malebolgia/lockers,rc

var global = initLocker(new int)

lock global as local:
    echo atomicRC local
    
    var owner2 = local
    echo atomicRC local

    # echo owner2[]
    let ouo= local
    echo atomicRC local

    proc x(g:var ref int)=
        let ouo= local

        echo atomicRC g
        
        echo "hi"
        g[] = 1
        echo g[]
    x(local)

    #will arc do anything after end of this block?