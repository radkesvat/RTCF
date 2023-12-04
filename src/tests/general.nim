import pretty,sugar,rope,strutils,stringview
import stew/byteutils



# var sv = newStringView(cap = 0)

# var x = "12345679"

# sv.write(x)

# sv.buf[0] = 'y'


# var sequence = bytes(sv)
# print sequence 

# sv.buf[0] = 'y'
# print sequence

var str = "abc"
prepareMutation(str)
var sequence {.cursor.} = cast[seq[char]](str)
str[0] = 'x'
echo str , " : ", sequence
#    xbc : @['a', 'b', 'c']

# var s = cast[seq[byte]](x)

# print s


