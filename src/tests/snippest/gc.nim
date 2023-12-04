
# API says:
proc GC_enableMarkAndSweep*() =
  ## For `--gc:orc` an alias for `GC_enableOrc`.
  GC_enableOrc()

proc GC_disableMarkAndSweep*() =
  ## For `--gc:orc` an alias for `GC_disableOrc`.
  GC_disableOrc()



echo "hi"