function duration(seconds) {
	hours = int(seconds / 3600)
	minutes = int((seconds - (hours * 3600)) / 60)
	seconds = seconds % 60
	return sprintf("%02d:%02d:%02d", hours, minutes, seconds)
}

BEGIN {
	OFS="!"
}
{
	build_time=now-$2
	path_n=split($1, paths, "/")
	print paths[path_n], duration(build_time)
}
