# Copyright (c) 2012-2017 Bryan Drewery <bdrewery@FreeBSD.org>
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.


# Parse the .poudriere files created during build into a JSON format
# that the web interface can fetch and use with jQuery. See
# common.sh build_json() for how it is used

function group_type(type) {
  if (type == "svn_url")
    return "string"
  if (type == "setname")
    return "string"
  if (type == "ptname")
    return "string"
  if (type == "jailname")
    return "string"
  if (type == "buildname")
    return "string"
  if (type == "mastername")
    return "string"
  if (type == "started")
    return "string"
  if (type == "ended")
    return "string"
  if (type == "builders")
    return "array"
  if (type == "jobs")
    return "array"
  if (type == "status")
    return "string"
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

# Print out impact/skipped counts
function display_skipped() {
  print "\"skipped\":{"
  for (pkgname in skipped_count)
    print "\"" pkgname "\":" skipped_count[pkgname] ","
  print "}\n"
}

function originspec_decode(originspec, originspec_items) {
  split(originspec, originspec_items, "@")
  # 1 = origin
  # 2 = FLAVOR
  # 3 = DEP_ARGS
}

function end_type() {
  if (in_type) {
    # Close out ports
    if (in_type == "ports") {
      for (port_status_type in ports_count) {
	print "\"" port_status_type "\":["
	for (i = 0; i < ports_count[port_status_type]; i++) {
	  print "{"
          split(ports[port_status_type, i], build_reasons, " ")
          if (port_status_type != "remaining") {
            originspec_decode(build_reasons[1], originspec)
            print "\"origin\":\"" originspec[1] "\","
            if (originspec[2])
              print "\"flavor\":\"" originspec[2] "\","
            pkgname = build_reasons[2]
          } else {
            pkgname = build_reasons[1]
          }
          print "\"pkgname\":\"" pkgname "\","
          if (port_status_type == "built" ) {
	    print "\"elapsed\":\"" build_reasons[3] "\","
          } else if (port_status_type == "queued") {
            print "\"reason\":\"" build_reasons[3] "\","
          } else if (port_status_type == "remaining") {
	    print "\"status\":\"" build_reasons[2] "\","
          } else if (port_status_type == "failed") {
	    print "\"phase\":\"" build_reasons[3] "\","
	    print "\"errortype\":\"" build_reasons[4] "\","
	    print "\"elapsed\":\"" build_reasons[5] "\","
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

    gtype = group_type(in_type)
    if (gtype == "array")
      print "],"
    else if (gtype == "object")
      print "},"
    print "\n"
  }

  if (type) {
    print "\"" type "\":"
    gtype = group_type(type)
    if (gtype == "array")
      print "["
    else if (gtype == "object")
      print "{"
    in_type = type
  }
}
BEGIN {
  ORS=""
  in_type=""
  print "{\n"
}
{
  file_parts_count = split(FILENAME, file_parts, "/")
  filename = file_parts[file_parts_count]
  # Skip builders as status already contains enough information
  if (filename == ".poudriere.builders" || FILENAME ~ /\.swp/)
    next
  # Track how many ports are skipped per failed/ignored port
  if (filename == ".poudriere.ports.skipped") {
      if (!skipped_count[$3])
          skipped_count[$3] = 0
      skipped_count[$3] += 1
  }
  split(filename, file_split, "\.")
  type = file_split[3]
  group_id = file_split[4]

  if (type == "status" && group_id) {
    type = "jobs"
  } else if (type ~ /^stats/) {
    group_id = substr(type, 7)
    type = "stats"
  } else if (type ~ /^snap/) {
    group_id = substr(type, 6)
    type = "snap"
  }

  # Skip port list and builder list in mini
  if (mini && (type == "ports" || type == "jobs" || type == "snap")) {
    next
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
  } else if (type == "jobs") {
    print "{"
    print "\"id\":\"" group_id "\","
    if (split($0, status_a, ":") > 2) {
      print "\"status\":\""  status_a[1] "\","
      originspec_decode(status_a[2], originspec)
      print "\"origin\":\""  originspec[1] "\","
      if (originspec[2])
        print "\"flavor\":\""  originspec[2] "\","
      print "\"pkgname\":\"" status_a[3] "\","
      print "\"started\":\"" status_a[4] "\","
      print "\"elapsed\":\"" status_a[5] "\""
    } else {
      print "\"status\":\"" $0 "\""
    }
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
  if (!mini) {
    display_skipped()
  }
  print "}\n"
}
