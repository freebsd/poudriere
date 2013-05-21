# Parse the .poudriere files created during build into a JSON format
# that the web interface can fetch and use with jQuery. See
# common.sh build_json() for how it is used

function group_type(type) {
  if (type == "builders")
    return "array"
  if (type == "status")
    return "array"
  return "object"
}

function escape(string) {
  # Remove escaped newlines
  gsub("\\n", "", string)
  # Remove all bad escapes
  gsub("\\\\", "", string)
  # Escape any nested quotes
  gsub(/"/, "\\\"", string)
  return string
}

function end_type() {
  if (in_type) {
    # Close out ports
    if (in_type == "ports") {
      for (port_status_type in ports_count) {
	print "\"" port_status_type "\":["
	for (i = 0; i < ports_count[port_status_type]; i++) {
	  split(ports[port_status_type, i], build_reasons, " ")
	  origin = build_reasons[1]
	  pkgname = build_reasons[2]
	  print "{"
	  print "\"origin\":\"" origin "\","
	  print "\"pkgname\":\"" pkgname "\","
	  if (port_status_type == "failed") {
	    print "\"phase\":\"" build_reasons[3] "\","
	  } else if (port_status_type == "ignored") {
	    reason_length = length(build_reasons)
	    for (n = 3; n <= reason_length; n++) {
	      if (n == 3)
	        reason = build_reasons[n]
	      else
		reason = reason " " build_reasons[n]
	    }
	    print "\"reason\":\"" escape(reason) "\","
	  } else if (port_status_type == "skipped") {
	    print "\"depends\":\"" build_reasons[3] "\","
	  }
	  print "},"
	}
	print "],"
      }
    }
    if (group_type(in_type) == "array")
      print "]"
    else
      print "}"
    print ",\n"
  }

  if (type) {
    print "\"" type "\":"
    if (group_type(type) == "array")
      print "["
    else
      print "{"
    in_type = type
  }
}
BEGIN {
  ORS=""
  in_type=""
  print "{\n"
  print "\"setname\": \"" setname "\","
  print "\"ptname\": \"" ptname "\","
  print "\"jail\": \"" jail "\","
  print "\"buildname\": \"" buildname "\","
}
{
  # Skip builders as status already contains enough information
  if (FILENAME == ".poudriere.builders" || FILENAME ~ /\.swp/)
    next
  split(FILENAME, file_split, "\.")
  type = file_split[3]
  group_id = file_split[4]

  if (type == "status" && !group_id)
    group_id = "main"
  if (type ~ /^stats/) {
    group_id = substr(type, 7)
    type = "stats"
  }


  # New type, close the old
  if (in_type != type) {
    end_type()
  }

  if (type == "ports") {
    # Group the ports by the status type (success,fail,etc)
    # It will be printed in end_type()
    if (!ports_count[group_id])
      ports_count[group_id] = 0
    count = ports_count[group_id]++
    # Group each port list into arrays
    ports[group_id, count] = $0
  } else if (type == "status") {
    print "{"
    print "\"id\":\"" group_id "\","
    print "\"status\":\"" $0 "\""
    print "},"
  } else {
    if (group_id)
      print "\"" group_id "\":" "\"" $0 "\","
    else
      print "\"" $0 "\","
  }

}
END {
  type=""
  end_type()
  print "}\n"
}
