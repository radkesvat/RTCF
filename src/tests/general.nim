import pretty,sugar,rope,strutils,stringview
import stew/byteutils



var datab = cast[ptr[char]](alloc0(100))
var data =  cast[ptr UncheckedArray[char]](addr datab[])
print datab
print data

data[0]='a'
data[1]='b'
data[2]='c'
# var uc = cast[UncheckedArray[char]](data)

# print data[0]
print data[][1]
