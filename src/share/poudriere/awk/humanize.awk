function humanize(number) {
	hum[1024**4]="TiB";
	hum[1024**3]="GiB";
	hum[1024**2]="MiB";
	hum[1024]="KiB";
	hum[0]="B";
	for (x=1024**4; x>=1024; x/=1024) {
		if (number >= x) {
			printf "%.2f %s", number/x, hum[x]
			return
		}
	}
}
{
	print humanize($1)
}
