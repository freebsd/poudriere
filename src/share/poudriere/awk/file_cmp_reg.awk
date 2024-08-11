NR == FNR       { patterns[++n] = $0; next }
BEGIN {
  bad=0
  linen=0
}
{
  line = $0
  pattern = patterns[++linen]
  if (match(line, pattern) > 0) {
    print linen ":good: " line
    next
  } else {
  print linen ":have    : " line
  print linen ":expected: " pattern
  bad=1
}
}
END {
  exit bad
}
