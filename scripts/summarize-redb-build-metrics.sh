#!/usr/bin/env bash
set -euo pipefail

metrics_file="${1:?usage: summarize-redb-build-metrics METRICS.tsv}"
[[ -s "${metrics_file}" ]] || {
    echo "redb build metrics summary: missing metrics: ${metrics_file}" >&2
    exit 1
}

awk -F '\t' '
    function fail(message) {
        print "redb build metrics summary: " message > "/dev/stderr"
        exit 1
    }

    NR == 1 {
        if ($0 != "variant\tbuild_elapsed_ms\tbinary_size_bytes")
            fail("invalid header")
        next
    }

    {
        if ($1 != "baseline" && $1 != "midpoint" &&
            $1 != "slice-comparison" && $1 != "key-comparisons" &&
            $1 != "optimized")
            fail("unknown variant: " $1)
        if (NF != 3 || seen[$1]++ || $2 !~ /^[0-9]+$/ || $2 == 0 ||
            $3 !~ /^[0-9]+$/ || $3 == 0)
            fail("invalid metrics row: " $0)
        elapsed[$1] = $2
        bytes[$1] = $3
        order[++count] = $1
    }

    END {
        expected[1] = "baseline"
        expected[2] = "midpoint"
        expected[3] = "slice-comparison"
        expected[4] = "key-comparisons"
        expected[5] = "optimized"
        for (variant = 1; variant <= 5; variant++)
            if (!(expected[variant] in elapsed))
                fail("missing " expected[variant] " row")
        print "variant\tbuild_elapsed_ms\tcompile_time_change_percent\tbinary_size_bytes\tcode_size_change_bytes\tcode_size_change_percent"
        for (row = 1; row <= count; row++) {
            variant = order[row]
            printf "%s\t%d\t%+.3f\t%d\t%+d\t%+.3f\n", \
                variant, elapsed[variant], \
                (elapsed[variant] / elapsed["baseline"] - 1) * 100, \
                bytes[variant], bytes[variant] - bytes["baseline"], \
                (bytes[variant] / bytes["baseline"] - 1) * 100
        }
    }
' "${metrics_file}"
