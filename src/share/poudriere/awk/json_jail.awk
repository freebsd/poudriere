{
  match($0, /"buildname":"[^"]*"/)
  buildname_group = substr($0, RSTART, RLENGTH)
  match(buildname_group, /:"[^"]*"/)
  buildname = substr(buildname_group, RSTART+2, RLENGTH-3)
  if (FILENAME ~ /latest\//) {
    data = "\"" buildname "\""
    buildname = "latest"
  } else {
    data = $0
  }
  print "\"" buildname "\":" data "" | "sort -n -k1,1 -t :"
}
