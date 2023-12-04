{.experimental: "views".}

proc take(a: openArray[int]) =
  echo a.len

proc main(s: seq[int]) =
  var x: openArray[int] = s # 'x' is a view into 's'
  # it is checked that 'x' does not outlive 's' and
  # that 's' is not mutated.
  for i in 0 .. high(x):
    echo x[i]
  take(x)
  
  take(x.toOpenArray(0, 1)) # slicing remains possible
  let y = x  # create a view from a view
  take y
  # it is checked that 'y' does not outlive 'x' and
  # that 'x' is not mutated as long as 'y' lives.
  take(x)


main(@[11, 22, 33])