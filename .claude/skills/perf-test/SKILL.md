---
name: perf-test
description: Performance and load testing skill. Runs service-level benchmarks and HTTP load tests with configurable profiles. Supports project-specific thresholds via addons.
user_invocable: true
---

# Performance & Load Test Skill

Runs performance benchmarks and load tests against your application.

## When to Use

- After implementing performance-sensitive features
- Before production deployment
- When the user asks to "run perf tests", "load test", or "stress test"

## Test Profiles

| Profile | Concurrent Users | Duration | Use Case |
|---------|-----------------|----------|----------|
| smoke | 5 | 10s | Quick sanity check |
| light | 10 | 30s | Development testing |
| medium | 25 | 60s | Pre-staging validation |
| stress | 50-100 | 120s | Pre-production validation |

## Workflow

### Step 1: Run Unit Benchmarks

If benchmark test files exist (e.g., `tests/performance/`), run them:

```bash
# Read test runner from config
TEST_RUNNER=$(grep -o '"runner"[[:space:]]*:[[:space:]]*"[^"]*"' platform.config.json 2>/dev/null | head -1 | sed 's/.*"runner"[[:space:]]*:[[:space:]]*"//;s/"$//')
: "${TEST_RUNNER:=}"

# Run benchmark tests
${TEST_RUNNER:+$TEST_RUNNER }npx jest tests/performance/ --forceExit 2>/dev/null || echo "No benchmark tests found"
```

### Step 2: Run HTTP Load Tests (if endpoints available)

Use `curl` for basic load testing or recommend k6/Artillery for comprehensive testing:

```bash
# Smoke test: 5 concurrent requests
for i in $(seq 1 5); do
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" <endpoint> &
done
wait
```

### Step 3: Analyze Results

Report metrics:
- **p50, p95, p99 latency** — response time percentiles
- **Error rate** — percentage of non-2xx responses
- **Throughput** — requests per second
- **Resource usage** — CPU, memory (if observable)

### Step 4: Apply Project-Specific Thresholds

**Read `.claude/perf-test-addons.md` if it exists.** This file contains:
- Custom benchmark thresholds (e.g., "encryption < 0.5ms")
- Specific endpoints to test
- Expected baseline performance
- Rate limiter configuration

### Output Format

```
## Performance Test Results

### Benchmarks
| Operation | Avg | p95 | Threshold | Status |
|-----------|-----|-----|-----------|--------|
| ... | ... | ... | ... | PASS/FAIL |

### Load Test (profile: medium)
| Metric | Value | Threshold | Status |
|--------|-------|-----------|--------|
| p50 latency | Xms | <200ms | PASS |
| p95 latency | Xms | <500ms | PASS |
| Error rate | X% | <5% | PASS |

### Verdict: PASS / WARN / FAIL
```
