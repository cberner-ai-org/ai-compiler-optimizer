#!/usr/bin/env bash
set -euo pipefail

results_file="${1:?usage: summarize-redb-phases.sh PHASE_RESULTS.tsv}"
[[ -s "${results_file}" ]] || {
    echo "redb phase summary: missing results: ${results_file}" >&2
    exit 1
}

gawk -F '\t' -f "${BASH_SOURCE[0]%/*}/student-t.awk" --source '
    function fail(message) {
        print "redb phase summary: " message > "/dev/stderr"
        exit 1
    }
    NR == 1 {
        if ($0 != "round\tvariant\tphase\toccurrence\telapsed_ms")
            fail("invalid header")
        next
    }
    {
        if (NF != 5 || $1 !~ /^[1-9][0-9]*$/ ||
            ($2 != "baseline" && $2 != "optimized") || $3 == "" ||
            index($3, SUBSEP) != 0 ||
            $4 !~ /^[1-9][0-9]*$/ || $5 !~ /^(0|[1-9][0-9]*)$/)
            fail("invalid results row: " $0)
        sample_key = $1 SUBSEP $2 SUBSEP $3 SUBSEP $4
        if (seen_sample[sample_key]++)
            fail("duplicate result for round " $1 " variant " $2 \
                " phase " $3 " occurrence " $4)
        elapsed[sample_key] = $5
        endpoint_key = $3 SUBSEP $4
        if (!seen_endpoint[endpoint_key]++) {
            endpoint_count++
            endpoint[endpoint_count] = endpoint_key
            phase[endpoint_key] = $3
            occurrence[endpoint_key] = $4
        }
        if ($1 > rounds)
            rounds = $1
    }
    END {
        if (rounds < 2)
            fail("at least two paired rounds are required")
        if (endpoint_count == 0)
            fail("no phase results")

        print "phase\toccurrence\trounds\tbaseline_mean_ms\toptimized_mean_ms\taggregate_speedup_percent\tpaired_mean_speedup_percent\tpaired_median_speedup_percent\tpaired_95ci_low_percent\tpaired_95ci_high_percent\tpaired_familywise_95ci_low_percent\tpaired_familywise_95ci_high_percent"
        for (endpoint_index = 1; endpoint_index <= endpoint_count; endpoint_index++) {
            endpoint_key = endpoint[endpoint_index]
            delete paired
            baseline_total = optimized_total = paired_total = 0
            for (round = 1; round <= rounds; round++) {
                baseline_key = round SUBSEP "baseline" SUBSEP endpoint_key
                optimized_key = round SUBSEP "optimized" SUBSEP endpoint_key
                if (!(baseline_key in elapsed) || !(optimized_key in elapsed))
                    fail("incomplete pair for phase " phase[endpoint_key] \
                        " occurrence " occurrence[endpoint_key] " in round " round)
                baseline_total += elapsed[baseline_key]
                optimized_total += elapsed[optimized_key]
                if (elapsed[optimized_key] == 0) {
                    if (elapsed[baseline_key] != 0)
                        fail("undefined speedup for phase " phase[endpoint_key] \
                            " occurrence " occurrence[endpoint_key] " in round " round)
                    paired[round] = 0
                } else {
                    paired[round] = \
                        (elapsed[baseline_key] / elapsed[optimized_key] - 1) * 100
                }
                paired_total += paired[round]
            }
            paired_mean = paired_total / rounds
            squared_deviation = 0
            for (round = 1; round <= rounds; round++)
                squared_deviation += (paired[round] - paired_mean) ^ 2
            standard_error = sqrt(squared_deviation / (rounds - 1)) / sqrt(rounds)
            confidence_radius = aco_student_t_critical(0.975, rounds - 1) * standard_error
            familywise_radius = aco_student_t_critical(1 - 0.05 / (2 * endpoint_count), rounds - 1) * standard_error
            asort(paired)
            median = rounds % 2 ? paired[(rounds + 1) / 2] : \
                (paired[rounds / 2] + paired[rounds / 2 + 1]) / 2
            printf "%s\t%d\t%d\t%.3f\t%.3f\t%+.3f\t%+.3f\t%+.3f\t%+.3f\t%+.3f\t%+.3f\t%+.3f\n", \
                phase[endpoint_key], occurrence[endpoint_key], rounds, \
                baseline_total / rounds, optimized_total / rounds, \
                optimized_total == 0 ? 0 : \
                    (baseline_total / optimized_total - 1) * 100, paired_mean, median, \
                paired_mean - confidence_radius, paired_mean + confidence_radius, \
                paired_mean - familywise_radius, paired_mean + familywise_radius
        }
    }
' "${results_file}"
