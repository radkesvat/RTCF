import sugar


proc a =
  var v = 0
  proc b =
    var w = 2

    for x in 0..3:
      proc c = capture v, w, x:discard
      c()
  b()

  for x in 0..4:
    proc d = capture x:discard
    d()
