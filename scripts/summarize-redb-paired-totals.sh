#!/usr/bin/env bash
set -euo pipefail

results_file="${1:?usage: summarize-redb-paired-totals TOTAL_RESULTS.tsv}"
[[ -s "${results_file}" ]] || {
    echo "redb paired total summary: missing results: ${results_file}" >&2
    exit 1
}

gawk -F '\t' -f "${BASH_SOURCE[0]%/*}/student-t.awk" --source '
    function fail(message) {
        print "redb paired total summary: " message > "/dev/stderr"
        exit 1
    }

    NR == 1 {
        if ($0 != "round\tvariant\telapsed_ns")
            fail("invalid header")
        next
    }

    {
        if (NF != 3 || $1 !~ /^[1-9][0-9]*$/ ||
            ($2 != "baseline" && $2 != "optimized") ||
            $3 !~ /^[1-9][0-9]*$/)
            fail("invalid results row: " $0)
        key = $1 SUBSEP $2
        if (seen[key]++)
            fail("duplicate result for round " $1 " variant " $2)
        elapsed[key] = $3
        if ($1 > rounds)
            rounds = $1
    }

    END {
        if (rounds < 2)
            fail("at least two paired rounds are required")

        for (round = 1; round <= rounds; round++) {
            baseline_key = round SUBSEP "baseline"
            optimized_key = round SUBSEP "optimized"
            if (!(baseline_key in elapsed) || !(optimized_key in elapsed))
                fail("incomplete result pair for round " round)
            baseline_total += elapsed[baseline_key]
            optimized_total += elapsed[optimized_key]
            paired[round] = (elapsed[baseline_key] / elapsed[optimized_key] - 1) * 100
            paired_total += paired[round]
        }

        paired_mean = paired_total / rounds
        squared_deviation = 0
        for (round = 1; round <= rounds; round++)
            squared_deviation += (paired[round] - paired_mean) ^ 2
        paired_standard_deviation = sqrt(squared_deviation / (rounds - 1))
        confidence_radius = \
            aco_student_t_critical(0.975, rounds - 1) * paired_standard_deviation / sqrt(rounds)
        asort(paired)

        print "rounds\tbaseline_mean_s\toptimized_mean_s\taggregate_speedup_percent\tpaired_mean_speedup_percent\tpaired_median_speedup_percent\tpaired_95ci_low_percent\tpaired_95ci_high_percent"
        printf "%d\t%.3f\t%.3f\t%+.3f\t%+.3f\t%+.3f\t%+.3f\t%+.3f\n", \
            rounds, \
            baseline_total / rounds / 1000000000, \
            optimized_total / rounds / 1000000000, \
            (baseline_total / optimized_total - 1) * 100, \
            paired_mean, \
            (rounds % 2 ? paired[(rounds + 1) / 2] : \
                (paired[rounds / 2] + paired[rounds / 2 + 1]) / 2), \
            paired_mean - confidence_radius, \
            paired_mean + confidence_radius
    }
' "${results_file}"
