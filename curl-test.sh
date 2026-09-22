#!/usr/bin/env bash

# Copyright (c) 2026 Lionel Guo
# Email: lionelliguo@gmail.com
#
# Generic curl performance test: timing, status, success rate, and retries.
set -u

PROGRAM=${0##*/}
URL=""
METHOD=""
DATA=""
COUNT=10
MAX_ATTEMPTS=3
RETRY_SLEEP=1
CONNECT_TIMEOUT=5
MAX_TIME=20
INSECURE=0
VERBOSE=0
HEADERS=()
EXTRA_CURL_ARGS=()

usage() {
  cat <<EOF
Usage:
  $PROGRAM --url URL [options]
  $PROGRAM [options] -- [curl options] URL

Options:
  -u, --url URL                 Target URL
  -X, --method METHOD           HTTP method, e.g. GET or POST
  -H, --header HEADER           Header; may be repeated
  -d, --data DATA               Request body
  -n, --count NUMBER            Test runs (default: $COUNT)
      --max-attempts NUMBER     Attempts per run (default: $MAX_ATTEMPTS)
      --retry-sleep SECONDS     Delay between attempts (default: $RETRY_SLEEP)
      --connect-timeout SEC     Connection timeout (default: $CONNECT_TIMEOUT)
      --max-time SEC            Total timeout per attempt (default: $MAX_TIME)
  -k, --insecure                Skip TLS certificate verification
  -v, --verbose                 Show curl errors and diagnostics
  -h, --help                    Show help

Examples:
  $PROGRAM --url https://example.com --count 20

  $PROGRAM --url https://example.com/api -X POST \
    -H 'Content-Type: application/json' -d '{"key":"value"}' -n 50

  $PROGRAM --count 20 -- -X POST -H 'Content-Type: application/json' \
    --data '{"key":"value"}' https://example.com/api

Success means curl exited normally and HTTP status was 2xx or 3xx.
Only successful runs are included in performance averages.
EOF
}

die() {
  echo "Error: $*" >&2
  echo "Run '$PROGRAM --help' for usage." >&2
  exit 2
}

positive_integer() { [[ $1 =~ ^[1-9][0-9]*$ ]]; }
non_negative_number() { [[ $1 =~ ^([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]]; }

while (($#)); do
  case $1 in
    -u|--url)              (($# >= 2)) || die "$1 requires a value"; URL=$2; shift 2 ;;
    -X|--method)           (($# >= 2)) || die "$1 requires a value"; METHOD=$2; shift 2 ;;
    -H|--header)           (($# >= 2)) || die "$1 requires a value"; HEADERS+=("$2"); shift 2 ;;
    -d|--data)             (($# >= 2)) || die "$1 requires a value"; DATA=$2; shift 2 ;;
    -n|--count)            (($# >= 2)) || die "$1 requires a value"; COUNT=$2; shift 2 ;;
    --max-attempts)        (($# >= 2)) || die "$1 requires a value"; MAX_ATTEMPTS=$2; shift 2 ;;
    --retry-sleep)         (($# >= 2)) || die "$1 requires a value"; RETRY_SLEEP=$2; shift 2 ;;
    --connect-timeout)     (($# >= 2)) || die "$1 requires a value"; CONNECT_TIMEOUT=$2; shift 2 ;;
    --max-time)            (($# >= 2)) || die "$1 requires a value"; MAX_TIME=$2; shift 2 ;;
    -k|--insecure)         INSECURE=1; shift ;;
    -v|--verbose)          VERBOSE=1; shift ;;
    -h|--help)             usage; exit 0 ;;
    --)                    shift; EXTRA_CURL_ARGS=("$@"); break ;;
    *)                     die "unknown option: $1" ;;
  esac
done

command -v curl >/dev/null 2>&1 || die "curl is not installed"
command -v awk >/dev/null 2>&1 || die "awk is not installed"
positive_integer "$COUNT" || die "--count must be a positive integer"
positive_integer "$MAX_ATTEMPTS" || die "--max-attempts must be a positive integer"
non_negative_number "$RETRY_SLEEP" || die "--retry-sleep must be non-negative"
non_negative_number "$CONNECT_TIMEOUT" || die "--connect-timeout must be non-negative"
non_negative_number "$MAX_TIME" || die "--max-time must be non-negative"
[[ -n $URL || ${#EXTRA_CURL_ARGS[@]} -gt 0 ]] || die "a URL is required"

CURL_ARGS=()
[[ -n $METHOD ]] && CURL_ARGS+=(--request "$METHOD")
for header in "${HEADERS[@]}"; do CURL_ARGS+=(--header "$header"); done
[[ -n $DATA ]] && CURL_ARGS+=(--data "$DATA")
((INSECURE)) && CURL_ARGS+=(--insecure)
CURL_ARGS+=("${EXTRA_CURL_ARGS[@]}")
[[ -n $URL ]] && CURL_ARGS+=("$URL")

FORMAT='%{time_namelookup}|%{time_connect}|%{time_pretransfer}|%{time_appconnect}|%{time_starttransfer}|%{time_total}|%{speed_download}|%{http_code}'

succ=0; cnt_success=0; cnt_failure=0
cnt_http2xx=0; cnt_http3xx=0; cnt_http4xx=0; cnt_http5xx=0; cnt_http000=0
sum_retries=0; max_retries_seen=0
sum_dns=0; sum_connect=0; sum_pre=0; sum_tls=0; sum_ttfb=0; sum_total=0; sum_speed=0

echo "----------------------------------------------------------------------------"
echo "curl performance test"
printf 'Request: curl '; printf '%q ' "${CURL_ARGS[@]}"; echo
echo "Runs: $COUNT | Max attempts/run: $MAX_ATTEMPTS | Retry sleep: ${RETRY_SLEEP}s"
echo "Timeouts: connect=${CONNECT_TIMEOUT}s | total=${MAX_TIME}s | TLS verification: $([[ $INSECURE -eq 1 ]] && echo disabled || echo enabled)"
echo "----------------------------------------------------------------------------"

for ((i=1; i<=COUNT; i++)); do
  echo "Run #$i ..."
  attempts=0; run_success=0; raw=""; exit_code=0; http_code=000

  while ((attempts < MAX_ATTEMPTS)); do
    attempts=$((attempts + 1))
    RUNTIME_ARGS=(--silent --output /dev/null --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" --write-out "$FORMAT")
    ((VERBOSE)) && RUNTIME_ARGS+=(--show-error --verbose)

    # Put measurement options last so user-supplied -o/-w values cannot break parsing.
    raw=$(curl "${CURL_ARGS[@]}" "${RUNTIME_ARGS[@]}")
    exit_code=$?
    IFS='|' read -r dns connect pre tls ttfb total speed_bps http_code <<< "$raw"
    http_code=${http_code:-000}

    if ((exit_code == 0)) && [[ $http_code =~ ^[23][0-9][0-9]$ ]]; then
      run_success=1
      break
    fi
    ((attempts < MAX_ATTEMPTS)) && sleep "$RETRY_SLEEP"
  done

  echo "  curl_exit=$exit_code | http_code=$http_code | attempts=$attempts"
  case $http_code in
    2??) cnt_http2xx=$((cnt_http2xx + 1)) ;;
    3??) cnt_http3xx=$((cnt_http3xx + 1)) ;;
    4??) cnt_http4xx=$((cnt_http4xx + 1)) ;;
    5??) cnt_http5xx=$((cnt_http5xx + 1)) ;;
    *)   cnt_http000=$((cnt_http000 + 1)) ;;
  esac

  if ((run_success)); then
    succ=$((succ + 1)); cnt_success=$((cnt_success + 1))
    dns=${dns:-0}; connect=${connect:-0}; pre=${pre:-0}; tls=${tls:-0}
    ttfb=${ttfb:-0}; total=${total:-0}; speed_bps=${speed_bps:-0}
    speed_mib=$(awk -v n="$speed_bps" 'BEGIN {printf "%.3f", (n+0)/1048576}')
    echo "  DNS:$dns s | TCP:$connect s | TLS:$tls s | TTFB:$ttfb s | Total:$total s | Speed:$speed_mib MiB/s"
    sum_dns=$(awk -v a="$sum_dns" -v b="$dns" 'BEGIN {printf "%.6f",a+b}')
    sum_connect=$(awk -v a="$sum_connect" -v b="$connect" 'BEGIN {printf "%.6f",a+b}')
    sum_pre=$(awk -v a="$sum_pre" -v b="$pre" 'BEGIN {printf "%.6f",a+b}')
    sum_tls=$(awk -v a="$sum_tls" -v b="$tls" 'BEGIN {printf "%.6f",a+b}')
    sum_ttfb=$(awk -v a="$sum_ttfb" -v b="$ttfb" 'BEGIN {printf "%.6f",a+b}')
    sum_total=$(awk -v a="$sum_total" -v b="$total" 'BEGIN {printf "%.6f",a+b}')
    sum_speed=$(awk -v a="$sum_speed" -v b="$speed_mib" 'BEGIN {printf "%.6f",a+b}')
  else
    cnt_failure=$((cnt_failure + 1))
    echo "  FAILED (excluded from performance averages)"
  fi

  retries=$((attempts - 1)); sum_retries=$((sum_retries + retries))
  ((retries > max_retries_seen)) && max_retries_seen=$retries
done

echo "----------------------------------------------------------------------------"
if ((succ > 0)); then
  echo "Average over $succ successful runs:"
  awk -v dns="$sum_dns" -v conn="$sum_connect" -v pre="$sum_pre" -v tls="$sum_tls" \
      -v ttfb="$sum_ttfb" -v total="$sum_total" -v speed="$sum_speed" -v n="$succ" 'BEGIN {
    printf "DNS Lookup     : %.4f s\n", dns/n
    printf "Connect Time   : %.4f s\n", conn/n
    printf "TLS Handshake  : %.4f s\n", tls/n
    printf "Pretransfer    : %.4f s\n", pre/n
    printf "Start Transfer : %.4f s\n", ttfb/n
    printf "Total Time     : %.4f s\n", total/n
    printf "Avg Speed      : %.3f MiB/s\n", speed/n
  }'
else
  echo "No successful runs. Check URL, network, DNS, TLS, proxy, or server response."
fi

success_rate=$(awk -v ok="$cnt_success" -v n="$COUNT" 'BEGIN {printf "%.2f",ok*100/n}')
avg_retries=$(awk -v r="$sum_retries" -v n="$COUNT" 'BEGIN {printf "%.3f",r/n}')
echo "----------------------------------------------------------------------------"
echo "HTTP status summary (final attempt of each run):"
echo "  2xx: $cnt_http2xx | 3xx: $cnt_http3xx | 4xx: $cnt_http4xx | 5xx: $cnt_http5xx | other/000: $cnt_http000"
echo "  Success: $cnt_success | Failure: $cnt_failure | Success rate: ${success_rate}%"
echo "Retry summary:"
echo "  Average retries/run: $avg_retries | Maximum observed: $max_retries_seen / $((MAX_ATTEMPTS - 1))"
echo "----------------------------------------------------------------------------"

# Non-zero exit makes the script automation-friendly when any run failed.
((cnt_failure == 0))
