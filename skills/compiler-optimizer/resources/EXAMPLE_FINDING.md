# Example Finding: AMM Router

**Project:** `foundry.toml`
**Findings:** CO-001 (optimizer_runs) + CO-002 (via_ir) + CO-003 (version)

---

## Before

```toml
[profile.default]
optimizer = true
optimizer_runs = 200

src = "src"
out = "out"
libs = ["lib"]
```

```solidity
// src/Router.sol
pragma solidity ^0.8.0;
```

## After

```toml
[profile.default]
optimizer = true
optimizer_runs = 1_000_000
via_ir = true

[profile.dev]
optimizer = true
optimizer_runs = 200
via_ir = false

[profile.deploy]
optimizer = true
optimizer_runs = 1
via_ir = true
```

```solidity
pragma solidity 0.8.28;
```

## Findings Summary

| ID | Finding | Impact |
|----|---------|--------|
| CO-001 | `optimizer_runs` 200 → 1,000,000 | ~5–15% per-call gas reduction for high-frequency swap router |
| CO-002 | Add `via_ir = true` (production profile) | ~5–20% bytecode/gas savings on complex internal calls |
| CO-003 | `^0.8.0` → `0.8.28` (pinned) | Auto-unchecked loops + transient storage + all optimizer gains |

**Measure:** `forge build --sizes && forge test --gas-report` before and after
