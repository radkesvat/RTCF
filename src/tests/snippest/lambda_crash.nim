template foo(x: proc (y: string)) =
  let f = x
  f("abc")
  
foo(proc (y: string) = echo y)