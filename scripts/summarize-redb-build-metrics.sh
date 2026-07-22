#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "usage: summarize-redb-build-metrics [--schema auto|legacy-v1|current-v2] METRICS.tsv" >&2
}

# Retained metrics own the complete schema they were produced with. Consumers
# default to recognizing every supported schema, while the current image
# producer opts into current-v2 explicitly at its call site.
required_schema=auto
if [[ "${1:-}" == --schema ]]; then
    (( $# == 3 )) || {
        usage
        exit 2
    }
    required_schema="$2"
    shift 2
fi
(( $# == 1 )) || {
    usage
    exit 2
}
case "${required_schema}" in
    auto|legacy-v1|current-v2)
        ;;
    *)
        usage
        exit 2
        ;;
esac

metrics_file="$1"
[[ -s "${metrics_file}" ]] || {
    echo "redb build metrics summary: missing metrics: ${metrics_file}" >&2
    exit 1
}

awk -F '\t' -v required_schema="${required_schema}" '
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
        if ($1 != "baseline" && $1 != "three-way-compare" && $1 != "midpoint" &&
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

        actual_schema = ("three-way-compare" in elapsed) \
            ? "current-v2" : "legacy-v1"
        if (required_schema != "auto" && required_schema != actual_schema)
            fail("expected " required_schema " schema; found " actual_schema)

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
