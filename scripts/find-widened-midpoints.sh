#!/usr/bin/env bash
set -euo pipefail

ir_path="${1:?usage: find-widened-midpoints.sh LLVM_IR_FILE}"
[[ -f "${ir_path}" ]] || {
    echo "LLVM IR file does not exist: ${ir_path}" >&2
    exit 1
}

awk '
function clear(values, key) {
    for (key in values)
        delete values[key]
}

function integer_type_index(start, cursor) {
    for (cursor = start; cursor <= NF; cursor++)
        if ($cursor == "i128")
            return cursor
    return 0
}

BEGIN {
    OFS = "\t"
    function_name = "<module>"
    print "pattern", "function", "line", "left", "right"
}

/^define .*@.*\(/ {
    function_name = $0
    sub(/^.*@/, "", function_name)
    sub(/\(.*/, "", function_name)
    clear(extensions)
    clear(addition_left)
    clear(addition_right)
    clear(shifts)
    next
}

$2 == "=" && $3 == "zext" && $4 == "i64" && $6 == "to" && $7 == "i128" {
    extensions[$1] = $5
    next
}

$2 == "=" && $3 == "add" {
    type_index = integer_type_index(4)
    if (type_index == 0 || type_index + 2 > NF)
        next
    left = $(type_index + 1)
    sub(/,$/, "", left)
    right = $(type_index + 2)
    addition_left[$1] = left
    addition_right[$1] = right
    next
}

$2 == "=" && $3 == "lshr" && $4 == "i128" {
    sum = $5
    sub(/,$/, "", sum)
    if ($6 == "1")
        shifts[$1] = sum
    next
}

$2 == "=" && $3 == "trunc" {
    type_index = integer_type_index(4)
    if (type_index == 0 || $(type_index + 2) != "to" || $(type_index + 3) != "i64")
        next

    shift = $(type_index + 1)
    sum = shifts[shift]
    left_extension = addition_left[sum]
    right_extension = addition_right[sum]
    left = extensions[left_extension]
    right = extensions[right_extension]
    if (left != "" && right != "")
        print "widened-unsigned-midpoint", function_name, NR, left, right
}
' "${ir_path}"
