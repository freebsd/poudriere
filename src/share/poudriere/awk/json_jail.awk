function get_value(key) {
  match($0, "\"" key "\":\"[^\"]*\"")
  key_group = substr($0, RSTART, RLENGTH)
  match(key_group, /:"[^"]*"/)
  value = substr(key_group, RSTART+2, RLENGTH-3)
  return value
}
function print_build(buildname, data) {
  if (buildname && data)
    print "\"" buildname "\":" data "" | "sort -n -k1,1 -t :"
}
{
  if (FILENAME ~ /latest\//)
    next
  else {
    data = $0
    buildname = get_value("buildname")
  }
  print_build(buildname, data)
}
END {
  if (buildname) {
    data = "\"" buildname "\""
    buildname = "latest"
    print_build(buildname, data)
  }
}
