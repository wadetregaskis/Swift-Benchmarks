### Median wall-clock time as a headed TSV

The benchmark names encode their parameters as `[src=… | set=… | mean=… | var=… | out=…] Algorithm name`, where `mean`, `var` and `out` are raw byte counts.  This `awk` script turns the benchmark tool's text output into a tab-separated file with a header row, normalising every wall-clock median to nanoseconds (the tool prints whichever of s / ms / µs / ns is most readable, so the unit varies row to row).

The header row matters: the `ChartResults` app uses its presence to switch into its general (schema-driven) mode.  Each categorical column other than the measure becomes a slicer; the numeric columns are selectable as the X axis.

```bash
swift package benchmark --target StringBuilding --no-progress | awk '
  BEGIN { print "source\tcharset\tmeanBytes\tvarianceBytes\toutputBytes\talgorithm\twallClockNanoseconds" }
  /^\[src=/ {
    line = $0; rb = index(line, "]")
    params = substr(line, 2, rb - 2); algo = substr(line, rb + 2)
    sub(/[ \t]+$/, "", algo)
    n = split(params, fields, / \| /)
    for (i = 1; i <= n; i++) {
      eq = index(fields[i], "="); key = substr(fields[i], 1, eq - 1); value = substr(fields[i], eq + 1)
      if      (key == "src")  src  = value
      else if (key == "set")  set  = value
      else if (key == "mean") mean = value
      else if (key == "var")  vari = value
      else if (key == "out")  out  = value
    }
  }
  /Time \(wall clock\)/ {
    unit = "us"
    if      (index($0, "(ns)")) unit = "ns"
    else if (index($0, "(ms)")) unit = "ms"
    else if (index($0, "(s)"))  unit = "s"
    split($0, cols, "│"); p50 = cols[5]; gsub(/[^0-9]/, "", p50)
    mult = (unit == "s") ? 1000000000 : (unit == "ms") ? 1000000 : (unit == "us") ? 1000 : 1
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", src, set, mean, vari, out, algo, (p50 * mult)
  }' > stringbuilding.tsv
```

Notes:

  * The unit detection is deliberately ASCII-only: it tests for `(ns)`, `(ms)` and `(s)`, and treats anything else as microseconds — so it doesn't matter whether the tool emits U+00B5 (µ) or U+03BC (μ) for the micro sign.
  * `cols[5]` is the p50 column (the `│`-separated cells are: «», metric, p0, p25, **p50**, p75, p90, p99, p100, samples, «»).  To export a different percentile, change the index (p75 = `cols[6]`, p90 = `cols[7]`, …).
  * To export more metrics, add similar blocks keyed on `/Malloc \(total\)/`, `/Memory \(resident peak\)/`, etc., widening the header to match.  (Allocation metrics require the benchmark package's jemalloc trait, which is currently disabled via `traits: []` in Package.swift; without it they read zero.)
