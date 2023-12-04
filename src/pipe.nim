import std/[tables, heapqueue, deques]


const buflen = 8192




type Pipe = ref object
    buf: UncheckedArray[buflen,char]
    tunnels:HeapQueue











