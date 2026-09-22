# curl-test.sh

Copyright (c) 2026 Lionel Guo  
Email: [lionelliguo@gmail.com](mailto:lionelliguo@gmail.com)

`curl-test.sh` is a general-purpose HTTP performance test script built on curl. It repeatedly sends a request and reports connection timing, server response timing, success rate, HTTP status distribution, and retry statistics.

The script supports regular GET requests, JSON POST requests, and custom curl arguments. Response bodies are discarded; only performance metrics are retained. It is intended for development, testing, and troubleshooting, not as a professional load-testing tool.

## Features

- Supports GET, POST, and other HTTP methods
- Supports multiple request headers and a request body
- Accepts native curl arguments after `--`
- Configurable run count, attempts, retry delay, and timeouts
- Reports DNS, TCP, TLS, TTFB, total time, and download speed
- Summarizes 2xx, 3xx, 4xx, 5xx, and other status codes
- Reports success rate and retry statistics
- Excludes failed runs from performance averages
- Verifies TLS certificates by default
- Returns a non-zero exit status if any run fails

## Requirements

The following commands are required:

- Bash
- curl
- awk

They are usually preinstalled on macOS and most Linux distributions. Check them with:

```bash
command -v bash curl awk
```

## Quick start

Open the script directory:

```bash
cd /Users/lionelliguo/curl-test
```

Make the script executable if necessary:

```bash
chmod +x curl-test.sh
```

Run 10 tests using the default settings:

```bash
./curl-test.sh --url "https://example.com"
```

Run 20 tests:

```bash
./curl-test.sh \
  --url "https://example.com" \
  --count 20
```

## Usage

The script supports two invocation styles.

### Structured options

```text
./curl-test.sh --url URL [options]
```

This form is convenient for common GET and POST requests.

### Native curl arguments

```text
./curl-test.sh [options] -- [curl options] URL
```

`--` marks the end of script options. Everything after it is passed to curl, which is useful for authentication, proxies, file uploads, and other advanced requests.

## Options

| Option | Description | Default |
| --- | --- | --- |
| `-u, --url URL` | Target URL | Required unless supplied after `--` |
| `-X, --method METHOD` | HTTP method, such as GET, POST, or PUT | Determined by curl |
| `-H, --header HEADER` | Request header; may be repeated | None |
| `-d, --data DATA` | Request body | None |
| `-n, --count NUMBER` | Number of test runs | `10` |
| `--max-attempts NUMBER` | Maximum attempts per run, including the first request | `3` |
| `--retry-sleep SECONDS` | Delay between attempts | `1` second |
| `--connect-timeout SEC` | Connection timeout per attempt | `5` seconds |
| `--max-time SEC` | Total timeout per attempt | `20` seconds |
| `-k, --insecure` | Skip TLS certificate verification | Disabled |
| `-v, --verbose` | Show curl errors and diagnostic output | Disabled |
| `-h, --help` | Show built-in help | — |

`--count` and `--max-attempts` must be positive integers. Time values may be non-negative integers or decimals.

## Examples

### GET request

```bash
./curl-test.sh \
  --url "https://example.com/api/health" \
  --count 20
```

### JSON POST request

```bash
./curl-test.sh \
  --url "https://example.com/api/items" \
  --method POST \
  --header "Content-Type: application/json" \
  --data '{"name":"demo","enabled":true}' \
  --count 50
```

### Multiple headers

```bash
./curl-test.sh \
  --url "https://example.com/api/profile" \
  --header "Accept: application/json" \
  --header "Authorization: Bearer YOUR_TOKEN" \
  --count 10
```

Do not store real credentials in the script or commit them to version control. Pass secrets through environment variables instead:

```bash
API_TOKEN="your-token"

./curl-test.sh \
  --url "https://example.com/api/profile" \
  --header "Authorization: Bearer ${API_TOKEN}"
```

### Retry and timeout settings

```bash
./curl-test.sh \
  --url "https://example.com" \
  --count 30 \
  --max-attempts 4 \
  --retry-sleep 0.5 \
  --connect-timeout 3 \
  --max-time 10
```

`--max-attempts 4` means at most four requests per run: the initial request plus up to three retries.

### Native curl arguments

```bash
./curl-test.sh \
  --count 20 \
  -- \
  -X POST \
  -H "Content-Type: application/json" \
  --data '{"key":"value"}' \
  "https://example.com/api"
```

### Diagnostic output

```bash
./curl-test.sh \
  --url "https://example.com" \
  --count 1 \
  --verbose
```

### Self-signed certificate

```bash
./curl-test.sh \
  --url "https://test.example.internal" \
  --insecure
```

`--insecure` disables TLS certificate verification. Use it only in a trusted test environment.

## Success and retry behavior

A run is successful only when both conditions are met:

1. curl exits with status `0`.
2. The final HTTP response status is 2xx or 3xx.

Connection failures, timeouts, TLS errors, 4xx responses, and 5xx responses trigger another attempt until the request succeeds or reaches `--max-attempts`. A run that still fails is excluded from performance averages, but it remains included in failure, status-code, and retry statistics.

The HTTP status summary uses the final attempt from each run. When no HTTP response is available, the status is normally reported as `000`.

## Metrics

| Metric | Meaning |
| --- | --- |
| `DNS Lookup` | Cumulative time until name resolution completed |
| `Connect Time` | Cumulative time until the TCP connection completed |
| `TLS Handshake` | Cumulative time until the TLS handshake completed; may be `0` for HTTP |
| `Pretransfer` | Cumulative time until curl was ready to transfer data |
| `Start Transfer` / `TTFB` | Cumulative time until the first response byte arrived |
| `Total Time` | Total request duration |
| `Avg Speed` | Average download speed reported by curl, in MiB/s |

These curl values are cumulative timestamps. For example, estimate TLS negotiation time with `TLS Handshake - Connect Time`, and approximate server wait time with `TTFB - Pretransfer`.

## Example output

```text
Run #1 ...
  curl_exit=0 | http_code=200 | attempts=1
  DNS:0.005000 s | TCP:0.020000 s | TLS:0.080000 s | TTFB:0.120000 s | Total:0.125000 s | Speed:0.012 MiB/s
```

After all runs, the script reports:

- Performance averages for successful runs
- HTTP status-code distribution
- Success count, failure count, and success rate
- Average and maximum retry counts

## Exit status

| Status | Meaning |
| --- | --- |
| `0` | Every test run succeeded |
| `1` | At least one test run failed |
| `2` | Invalid arguments or a missing dependency |

The exit status can be used in automation:

```bash
if ./curl-test.sh --url "https://example.com/health" --count 5; then
  echo "All tests passed"
else
  echo "At least one test failed"
fi
```

## Safety notes

- Test only services you are authorized to access.
- Large run counts increase server load. Start with a small `--count` in production.
- POST, PUT, PATCH, and DELETE requests may modify data on every attempt and retry.
- Confirm that repeated execution is safe before testing or retrying a non-idempotent endpoint.
- Requests are sequential, not concurrent. Use a dedicated load-testing tool for throughput or concurrency testing.
- Response bodies are discarded, so download speed is less meaningful for small responses.
- `--insecure` weakens TLS security and should not be the production default.

## Built-in help

```bash
./curl-test.sh --help
```
