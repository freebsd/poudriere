function get_value(key) {
  match($0, "\"" key "\":\"[^\"]*\"")
  key_group = substr($0, RSTART, RLENGTH)
  match(key_group, /:"[^"]*"/)
  value = substr(key_group, RSTART+2, RLENGTH-3)
  return value
}
function print_value(key, end) {
  printf "\"" key "\":\"" get_value(key) "\"" end
}
{
  split(FILENAME, paths, "/")
  jail=paths[1]
  printf "\"" jail "\":{"
  printf "\"latest\":" $0 ","
  print_value("mastername", ",")
  print_value("jailname", ",")
  print_value("ptname", ",")
  print_value("setname", ",")
  print_value("status")
  print "}"
  next

  if (FILENAME ~ /latest\//) {
    data = "\"" buildname "\""
    buildname = "latest"
  } else {
    data = $0
  }
  print "\"" buildname "\":" data "" | "sort -n -k1,1 -t :"
}
