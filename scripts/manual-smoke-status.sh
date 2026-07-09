#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKLIST="$ROOT/docs/manual-smoke-tests/mengo-v1.md"
REQUIRE_COMPLETE=0

usage() {
    cat <<'EOF'
Usage: scripts/manual-smoke-status.sh [--require-complete] [checklist.md]

Summarize the Mengo Desktop V1 manual smoke checklist.

Options:
  --require-complete  Exit nonzero if any checklist item is still unchecked.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --require-complete)
            REQUIRE_COMPLETE=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "ERROR: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            CHECKLIST="$1"
            shift
            ;;
    esac
done

[ -f "$CHECKLIST" ] || {
    echo "ERROR: checklist not found: $CHECKLIST" >&2
    exit 1
}

awk -v require_complete="$REQUIRE_COMPLETE" '
function ensure_section(name) {
    if (!(name in seen)) {
        seen[name] = 1
        order[++section_count] = name
    }
}

BEGIN {
    section = "Unsectioned"
    ensure_section(section)
}

/^##[[:space:]]+/ {
    section = $0
    sub(/^##[[:space:]]+/, "", section)
    ensure_section(section)
    next
}

/^- \[[ xX]\][[:space:]]+/ {
    status = substr($0, 4, 1)
    item = $0
    sub(/^- \[[ xX]\][[:space:]]+/, "", item)

    total[section]++
    total_items++

    if (status == "x" || status == "X") {
        done[section]++
        done_items++
    } else {
        open[section]++
        open_items++
        blockers[++blocker_count] = section ": " item
    }
}

END {
    print "# Mengo Desktop V1 Manual Smoke Status"
    print ""
    printf("Checklist: %s\n", FILENAME)
    printf("Total: %d/%d complete", done_items, total_items)
    if (total_items > 0) {
        printf(" (%.0f%%)", done_items * 100 / total_items)
    }
    print ""
    print ""
    print "## Sections"
    for (i = 1; i <= section_count; i++) {
        name = order[i]
        if (total[name] == 0) {
            continue
        }
        printf("- %s: %d/%d complete", name, done[name], total[name])
        if (open[name] > 0) {
            printf(", %d open", open[name])
        }
        print ""
    }

    print ""
    if (blocker_count > 0) {
        print "## Open Manual Gates"
        for (i = 1; i <= blocker_count; i++) {
            print "- " blockers[i]
        }
    } else {
        print "## Open Manual Gates"
        print "- none"
    }

    if (require_complete && blocker_count > 0) {
        exit 1
    }
}
' "$CHECKLIST"
