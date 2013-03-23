{
	hum[1024**4]="TB";
	hum[1024**3]="GB";
	hum[1024**2]="MB";
	hum[1024]="KB";
	hum[0]="B";
	for (x=1024**4; x>=1024; x/=1024) {
		if ($1 >= x) {
			printf "%.2f %s\t%s\n", $1/x, hum[x], $2;
			break
		}
	}
}
