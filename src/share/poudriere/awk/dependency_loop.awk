BEGIN {
	i = 0
}
{
	if ($0 == "cycle in data") {
		i = i + 1
		next
	}
	if (a[i])
		a[i] = a[i] " " $1
	else
		a[i] = $1
}
END {
	for (n in a)
		print "These packages depend on each other: " a[n]
}
