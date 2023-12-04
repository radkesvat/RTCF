template `while`(lt:bool,code:untyped){.dirty.}=
    block loop:
        while lt:
            code

proc test_blocks()=
    `while` true:
        echo "hi"
        block my_block:
            echo "inside"
            break loop 
        echo "outside"       

            
test_blocks()