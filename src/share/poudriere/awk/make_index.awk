BEGIN {
	nblines=0
	while ((getline < indf) > 0) {
		sub(/\//, "\/", $2);
		patterns[nblines] = "^"$2"$";
		subst[nblines] = $1;
		a_edep[nblines] = $8;
		a_pdep[nblines] = $9;
		a_fdep[nblines] = $10;
		a_bdep[nblines] = $11;
		a_rdep[nblines] = $12;
		nblines++;
	}
	OFS="|"
}
{
	edep = $8;
	pdep = $9;
	fdep = $10;
	bdep = $11;
	rdep = $12;

	split($8, sedep, " ") ;
	split($9, sfdep, " ") ;
	split($10, spdep, " ") ;
	split($11, sbdep, " ") ;
	split($12, srdep, " ") ;

	for (i = 0; i < nblines; i++) {
		for (s in sedep)
			if ( sedep[s] ~ patterns[i] )
				edep = edep" "a_rdep[i];

		for (s in sfdep)
			if ( sfdep[s] ~ patterns[i] )
				fdep = fdep" "a_rdep[i];

		for (s in spdep)
			if ( spdep[s] ~ patterns[i] )
				pdep = pdep" "a_rdep[i];

		for (s in sbdep)
			if ( sbdep[s] ~ patterns[i] )
				bdep = bdep" "a_rdep[i];

		for (s in srdep)
			if ( srdep[s] ~ patterns[i] )
				rdep = rdep" "a_rdep[i];
	}

	edep = uniq(edep, patterns, subst);
	fdep = uniq(fdep, patterns, subst);
	pdep = uniq(pdep, patterns, subst);
	bdep = uniq(bdep, patterns, subst);
	rdep = uniq(rdep, patterns, subst);

	sub(/^ /, "", edep);
	sub(/^ /, "", fdep);
	sub(/^ /, "", pdep);
	sub(/^ /, "", bdep);
	sub(/^ /, "", rdep);
	print $1,$2,$3,$4,$5,$6,$7,bdep,rdep,$13,edep,pdep,fdep
}

function array_s(array, str, i) {
	for (i in array)
		if (array[i] == str)
			return 0;

	return -1;
}

function uniq(as, pat, subst, B) {
	split(as, A, " ");
	as = "";

	for (a in A) {
		if (array_s(B, A[a]) != 0) {
			str = A[a];
			for (j in subst)
				sub(pat[j], subst[j], str);

			as = as" "str
			B[i] = A[a];
			i++;
		}
	}

	return as;
}
