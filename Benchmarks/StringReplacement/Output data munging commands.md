### Median wall clock time as TSV

> egrep '^\[|│ Time \(wall clock\)' FILE | sed -E 's/│.*\((.*)\)[^│]*│[^│]*│[^│]*│ *([0-9]*).*/\2 \1/g ; s/^([0-9]+) s$/\1,000,000,000/g ; s/^([0-9]+) μs$/\1,000/g ; s/^([0-9]+) ms$/\1,000,000/g ; s/^([0-9]+) ns$/\1/g ; s/([0-9])([0-9]{3})/\1,\2/g' | sed -E '/\[.*/N ; s/\n/\t/ ; s:\[([^,]+), ([,0-9]+) / ([,0-9]+), ([^]]+)] :\1\t\2\t\3\t\4\t: ; s/\[Empty string] /Empty string\t0\t0\tLength irrelevant\t/'
