#!/bin/bash
# Run the commit.show CLI in JSON mode, render a Markdown summary, and
# (optionally) post or update a sticky pull-request comment.
#
# Inputs are passed in as environment variables by action.yml. The CLI
# is the single source of truth for the audit JSON schema (v1 stable);
# this script just glues the JSON to a Markdown comment and to the
# Actions output channel.

set -euo pipefail

# ── 1. Resolve the target ────────────────────────────────────
TARGET="${INPUT_TARGET:-}"
if [ -z "$TARGET" ]; then
  TARGET="github.com/${GH_REPO}"
fi

# ── 2. Build CLI args ────────────────────────────────────────
ARGS=(audit "$TARGET" --json)
if [ "${INPUT_REFRESH:-false}" = "true" ]; then
  ARGS+=(--refresh)
fi

echo "→ commitshow ${ARGS[*]}"

# ── 3. Run the audit ─────────────────────────────────────────
JSON=$(npx -y commitshow@latest "${ARGS[@]}")

# Save the raw JSON for downstream debugging.
JSON_PATH="${RUNNER_TEMP:-/tmp}/commitshow-audit.json"
echo "$JSON" > "$JSON_PATH"
echo "JSON written to $JSON_PATH"

# ── 4. Pull stable fields ────────────────────────────────────
SCORE=$(echo "$JSON" | jq -r '.score.total // empty')
BAND=$(echo  "$JSON" | jq -r '.score.band // ""')
URL=$(echo   "$JSON" | jq -r '.project.url // ""')

# Surface as Action outputs for downstream steps.
{
  echo "score=${SCORE}"
  echo "band=${BAND}"
  echo "url=${URL}"
} >> "$GITHUB_OUTPUT"

# Job summary so the score is visible from the run page even when the
# action runs outside a pull request.
{
  echo "## commit.show audit"
  echo
  if [ -n "$SCORE" ]; then
    echo "Total score: **${SCORE} / 100**"
  else
    echo "Audit returned no score. See the JSON output above."
  fi
  if [ -n "$URL" ]; then
    echo
    echo "[Full report]($URL)"
  fi
} >> "$GITHUB_STEP_SUMMARY"

# ── 5. Build a Markdown comment ──────────────────────────────
COMMENT=$(echo "$JSON" | python3 - <<'PYEOF'
import json, sys

def bar(value, ceiling, width=20):
    if not ceiling:
        return ""
    filled = round(width * value / ceiling)
    return "▰" * filled + "▱" * (width - filled)

data = json.load(sys.stdin)
score    = data.get("score") or {}
project  = data.get("project") or {}
concerns = data.get("concerns") or []

total      = score.get("total")
total_max  = score.get("total_max", 100)
audit      = score.get("audit", 0)
audit_max  = score.get("audit_max", 50)
scout      = score.get("scout", 0)
scout_max  = score.get("scout_max", 30)
comm       = score.get("community", 0)
comm_max   = score.get("community_max", 20)
delta      = score.get("delta_since_last")

lines = []
if total is None:
    lines.append("### commit.show audit")
    lines.append("")
    lines.append("The audit did not return a score. Re-run with `refresh: true` or check the action logs.")
else:
    lines.append(f"### commit.show audit  ·  **{total} / {total_max}**")
    lines.append("")
    lines.append("```")
    lines.append(f"Audit  {audit:>2}/{audit_max}  {bar(audit, audit_max)}")
    lines.append(f"Scout  {scout:>2}/{scout_max}  {bar(scout, scout_max)}")
    lines.append(f"Comm.  {comm:>2}/{comm_max}  {bar(comm, comm_max)}")
    lines.append("```")
    if delta is not None:
        sign = "+" if delta > 0 else ""
        lines.append(f"_Δ {sign}{delta} since the last audit._")

bullets = [c.get("bullet", "").strip() for c in concerns if c.get("bullet")]
if bullets:
    lines.append("")
    lines.append("**Top concerns**")
    for b in bullets[:3]:
        lines.append(f"- {b}")

url = project.get("url", "")
if url:
    lines.append("")
    lines.append(f"[Full report on commit.show]({url})")

lines.append("")
lines.append("<sub><!--commitshow-audit-action--> Posted by [commitshow/audit-action](https://github.com/commitshow/audit-action).</sub>")
print("\n".join(lines))
PYEOF
)

# ── 6. Post or update the sticky pull-request comment ────────
MARKER="<!--commitshow-audit-action-->"
if [ "${INPUT_COMMENT:-true}" = "true" ] && [ -n "${GH_PR_NUMBER:-}" ]; then
  EXISTING_ID=$(gh api "repos/${GH_REPO}/issues/${GH_PR_NUMBER}/comments" \
                  --jq ".[] | select(.body | contains(\"${MARKER}\")) | .id" \
                | head -n 1)

  if [ -n "$EXISTING_ID" ]; then
    gh api -X PATCH "repos/${GH_REPO}/issues/comments/${EXISTING_ID}" \
      -f body="$COMMENT" >/dev/null
    echo "Updated sticky comment (id ${EXISTING_ID})."
  else
    gh api -X POST "repos/${GH_REPO}/issues/${GH_PR_NUMBER}/comments" \
      -f body="$COMMENT" >/dev/null
    echo "Posted new sticky comment."
  fi
fi

# ── 7. Optional quality-gate ─────────────────────────────────
if [ -n "${INPUT_FAIL_BELOW:-}" ]; then
  if [ -z "$SCORE" ]; then
    echo "::warning::fail-below was set but the audit returned no score; skipping the gate."
  elif [ "$SCORE" -lt "$INPUT_FAIL_BELOW" ]; then
    echo "::error::Score ${SCORE} is below the configured threshold of ${INPUT_FAIL_BELOW}."
    exit 1
  fi
fi
