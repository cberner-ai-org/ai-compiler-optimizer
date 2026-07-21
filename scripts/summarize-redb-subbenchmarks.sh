#!/usr/bin/env bash
set -euo pipefail

log_file="${1:?usage: summarize-redb-subbenchmarks RAW_BENCHMARK_LOG}"
[[ -s "${log_file}" ]] || {
    echo "redb sub-benchmark summary: missing log: ${log_file}" >&2
    exit 1
}

gawk -f "${BASH_SOURCE[0]%/*}/student-t.awk" --source '
    function fail(message) {
        print "redb sub-benchmark summary: " message > "/dev/stderr"
        exit 1
    }

    function record(benchmark, expected) {
        if (!match($0, / in ([0-9]+)ms/, elapsed))
            fail("could not parse elapsed time from: " $0)
        key = round SUBSEP variant SUBSEP benchmark
        totals[key] += elapsed[1]
        counts[key]++
        expected_counts[benchmark] = expected
    }

    /^\[round [0-9]+\/[0-9]+\] (baseline|optimized)/ {
        if (!match($0, /^\[round ([0-9]+)\/([0-9]+)\] (baseline|optimized)/, header))
            fail("could not parse round header: " $0)
        round = header[1] + 0
        rounds = header[2] + 0
        variant = header[3]
        next
    }

    /^\[(baseline|optimized)\] redb:/ {
        if (round == 0 || variant == "")
            fail("measurement appeared before its round header")
        if (index($0, "[" variant "]") != 1)
            fail("measurement variant disagrees with its round header")

        if ($0 ~ /Bulk loaded 5000000 items/)
            record("bulk_load", 1)
        else if ($0 ~ /Wrote 1000 individual items/)
            record("individual_writes", 1)
        else if ($0 ~ /Wrote 100 batches of 1000 items/)
            record("batch_writes", 1)
        else if ($0 ~ /Wrote 50000 individual items/)
            record("nosync_writes", 1)
        else if ($0 ~ /Random read 1000000 items/)
            record("random_reads", 2)
        else if ($0 ~ /Random range read 500000 x 10 elements/)
            record("random_range_reads", 2)
        else if ($0 ~ /Random read \(4 threads\)/)
            record("random_reads_4_threads", 1)
        else if ($0 ~ /Random read \(8 threads\)/)
            record("random_reads_8_threads", 1)
        else if ($0 ~ /Random read \(16 threads\)/)
            record("random_reads_16_threads", 1)
        else if ($0 ~ /Random read \(32 threads\)/)
            record("random_reads_32_threads", 1)
        else if ($0 ~ /Removed 2575500 items/)
            record("removals", 1)
        else if ($0 ~ /Compacted/)
            record("compaction", 1)
        next
    }

    END {
        if (rounds < 2)
            fail("at least two paired rounds are required")

        order[1] = "bulk_load"
        order[2] = "individual_writes"
        order[3] = "batch_writes"
        order[4] = "nosync_writes"
        order[5] = "random_reads"
        order[6] = "random_range_reads"
        order[7] = "random_reads_4_threads"
        order[8] = "random_reads_8_threads"
        order[9] = "random_reads_16_threads"
        order[10] = "random_reads_32_threads"
        order[11] = "removals"
        order[12] = "compaction"

        print "benchmark\trounds\traw_samples_per_variant\tbaseline_mean_ms\toptimized_mean_ms\taggregate_speedup_percent\tpaired_mean_speedup_percent\tpaired_median_speedup_percent\tpaired_95ci_low_percent\tpaired_95ci_high_percent\tpaired_familywise_95ci_low_percent\tpaired_familywise_95ci_high_percent"
        for (row = 1; row <= 12; row++) {
            benchmark = order[row]
            expected = expected_counts[benchmark]
            if (expected == 0)
                fail("missing benchmark: " benchmark)

            delete paired
            baseline_total = 0
            optimized_total = 0
            paired_total = 0
            for (sample_round = 1; sample_round <= rounds; sample_round++) {
                baseline_key = sample_round SUBSEP "baseline" SUBSEP benchmark
                optimized_key = sample_round SUBSEP "optimized" SUBSEP benchmark
                if (counts[baseline_key] != expected || counts[optimized_key] != expected)
                    fail("incomplete pair for " benchmark " in round " sample_round)
                baseline = totals[baseline_key] / counts[baseline_key]
                optimized = totals[optimized_key] / counts[optimized_key]
                baseline_total += baseline
                optimized_total += optimized
                paired[sample_round] = (baseline / optimized - 1) * 100
                paired_total += paired[sample_round]
            }

            baseline_mean = baseline_total / rounds
            optimized_mean = optimized_total / rounds
            paired_mean = paired_total / rounds
            squared_deviation = 0
            for (sample_round = 1; sample_round <= rounds; sample_round++)
                squared_deviation += (paired[sample_round] - paired_mean) ^ 2
            paired_standard_deviation = sqrt(squared_deviation / (rounds - 1))

            critical = aco_student_t_critical(0.975, rounds - 1)
            confidence_radius = critical * paired_standard_deviation / sqrt(rounds)
            # Twelve sub-benchmarks are inspected together. This Bonferroni
            # interval uses t_(1 - 0.05 / (2 * 12), rounds - 1) so simultaneous
            # coverage across the reported family is at least 95%.
            familywise_critical = \
                aco_student_t_critical(1 - 0.05 / (2 * 12), rounds - 1)
            familywise_confidence_radius = familywise_critical * paired_standard_deviation / sqrt(rounds)

            asort(paired)
            paired_median = rounds % 2 ? paired[(rounds + 1) / 2] : \
                (paired[rounds / 2] + paired[rounds / 2 + 1]) / 2
            printf "%s\t%d\t%d\t%.3f\t%.3f\t%+.3f\t%+.3f\t%+.3f\t%+.3f\t%+.3f\t%+.3f\t%+.3f\n", \
                benchmark, \
                rounds, \
                rounds * expected, \
                baseline_mean, \
                optimized_mean, \
                (baseline_mean / optimized_mean - 1) * 100, \
                paired_mean, \
                paired_median, \
                paired_mean - confidence_radius, \
                paired_mean + confidence_radius, \
                paired_mean - familywise_confidence_radius, \
                paired_mean + familywise_confidence_radius
        }
    }
' "${log_file}"
