#!/usr/bin/env bash
# report-to-control: POST one readiness event to Control. See README.md.
#
# Inputs arrive as RC_* environment variables (action.yml). Every path exits 0: a report must
# never decide the outcome of the job that sends it. Problems become ::warning:: annotations.
#
# The OIDC token is masked, kept out of argv (curl reads its headers from a 0600 file) and
# never printed. The request body is built by jq, never by string concatenation.

set -uo pipefail

KINDS="deployed verified migrated provisioned checked"
NAME_RE='^[a-z0-9][a-z0-9._-]{0,62}$'
MAX_DETAIL_BYTES=4096

OUT="${GITHUB_OUTPUT:-/dev/null}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}
lower() { trim "$1" | tr '[:upper:]' '[:lower:]'; }

warn() { echo "::warning title=report-to-control::$1"; }

# finish RESULT HTTP-CODE SUMMARY-TEXT — set the outputs, add the one summary line, exit 0.
finish() {
  {
    echo "result=$1"
    echo "http-code=$2"
  } >>"$OUT"
  echo "- **Report to Control** — $3" >>"$SUMMARY"
  exit 0
}

environment="$(lower "${RC_ENVIRONMENT:-}")"
component="$(lower "${RC_COMPONENT:-}")"
kind="$(lower "${RC_KIND:-}")"
# Unset means "not given" (success). Set but empty is an explicit value and counts as failure.
raw_status="$(lower "${RC_STATUS-success}")"
version="$(trim "${RC_VERSION:-}")"
version="${version:0:64}"
detail_in="$(trim "${RC_DETAIL:-}")"
audience="$(trim "${RC_AUDIENCE:-https://control.junctionnet.nl}")"
endpoint="$(trim "${RC_ENDPOINT:-https://control.junctionnet.nl/api/readiness/ingest}")"

label="\`${environment:-?}\` · \`${component:-?}\` · ${kind:-?}"

# --- status -----------------------------------------------------------------------------------
case "$raw_status" in
  success) status=success ;;
  skipped | cancelled)
    echo "::notice title=report-to-control::Status is ${raw_status}; nothing reported to Control."
    finish skipped "" "${label}: not reported (${raw_status})"
    ;;
  *) status=failure ;;
esac

# --- validate before spending a network call -------------------------------------------------
for tool in jq curl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    warn "$tool is not installed on this runner; nothing reported to Control."
    finish invalid "" "not reported ($tool missing)"
  fi
done

problems=()
[[ "$environment" =~ $NAME_RE ]] || problems+=("environment must match ${NAME_RE} after lowercasing")
[[ "$component" =~ $NAME_RE ]] || problems+=("component must match ${NAME_RE} after lowercasing")
[[ " $KINDS " == *" $kind "* && -n "$kind" ]] || problems+=("kind must be one of: ${KINDS// /, }")
if ((${#problems[@]})); then
  for p in "${problems[@]}"; do warn "$p"; done
  finish invalid "" "not reported (invalid input, see the step's warnings)"
fi

detail=null
if [[ -n "$detail_in" ]]; then
  if parsed="$(jq -c -s 'if length == 1 and (.[0] | type) == "object" then .[0] else error("not one object") end' \
    <<<"$detail_in" 2>/dev/null)"; then
    if (($(printf '%s' "$parsed" | wc -c) > MAX_DETAIL_BYTES)); then
      warn "detail is larger than ${MAX_DETAIL_BYTES} bytes; reporting without it."
    else
      detail="$parsed"
    fi
  else
    warn "detail is not a JSON object; reporting without it."
  fi
fi

# --- OIDC token ---------------------------------------------------------------------------------
if [[ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" || -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]]; then
  warn "No OIDC token available, so nothing was reported to Control. Give this job 'permissions: id-token: write' (plus 'contents: read'). Pull requests from forks never get one."
  finish no-token "" "${label}: not reported (no id-token: write permission)"
fi

umask 077
printf 'Authorization: bearer %s\n' "$ACTIONS_ID_TOKEN_REQUEST_TOKEN" >"$workdir/token-request.h"
audience_q="$(jq -rn --arg a "$audience" '$a | @uri')"

if ! token_json="$(curl -sS --fail --max-time 10 --retry 2 \
  -H @"$workdir/token-request.h" \
  "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=${audience_q}")"; then
  warn "Could not get an OIDC token from GitHub; nothing reported to Control."
  finish no-token "" "${label}: not reported (OIDC token request failed)"
fi
token="$(jq -r '.value // empty' <<<"$token_json" 2>/dev/null)"
unset token_json
if [[ -z "$token" ]]; then
  warn "GitHub returned no OIDC token; nothing reported to Control."
  finish no-token "" "${label}: not reported (empty OIDC token)"
fi
echo "::add-mask::${token}"
printf 'X-GitHub-OIDC-Token: %s\n' "$token" >"$workdir/report.h"
unset token

# --- report ------------------------------------------------------------------------------------
body="$(jq -nc \
  --arg environment "$environment" \
  --arg component "$component" \
  --arg kind "$kind" \
  --arg status "$status" \
  --arg version "$version" \
  --argjson detail "$detail" \
  '{environment: $environment, component: $component, kind: $kind, status: $status}
   + (if $version == "" then {} else {version: $version} end)
   + (if $detail == null then {} else {detail: $detail} end)')"

echo "Reporting to ${endpoint}: ${body}"

code="$(curl -sS --max-time 10 --retry 2 \
  -o "$workdir/response" -w '%{http_code}' \
  -X POST "$endpoint" \
  -H 'Content-Type: application/json' \
  -H @"$workdir/report.h" \
  --data-binary "$body")" || code=000
[[ "$code" =~ ^[0-9]{3}$ ]] || code=000

echo "Control answered HTTP ${code}"
if [[ -s "$workdir/response" ]]; then
  head -c 2000 "$workdir/response"
  echo
fi

label="${label} · ${status}"
case "$code" in
  201) finish posted "$code" "${label} → HTTP 201 (recorded)" ;;
  2??) finish posted "$code" "${label} → HTTP ${code} (already recorded)" ;;
  000)
    warn "Control could not be reached at ${endpoint}; the job is unaffected."
    finish unreachable "$code" "${label} → unreachable"
    ;;
  401) warn "Control refused the OIDC token (HTTP 401). Check the audience input: Control accepts only https://control.junctionnet.nl." ;;
  403) warn "Control refused ${GITHUB_REPOSITORY:-this repository} (HTTP 403): it is not on the readiness allowlist (apps/control/lib/board-repos.js, readiness: true, in junctionnet/developer-platform)." ;;
  400) warn "Control rejected the report body (HTTP 400); its answer is in the log above." ;;
  *) warn "Control answered HTTP ${code}; the job is unaffected." ;;
esac
finish rejected "$code" "${label} → HTTP ${code} (rejected)"
