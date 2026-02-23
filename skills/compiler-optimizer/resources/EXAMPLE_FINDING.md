# Compiler Optimizer Skill — Example Finding: AMM Protocol

## Contract Under Review

`foundry.toml` and `src/SwapRouter.sol` — A high-frequency DEX swap router
with complex internal call chains.

## Findings

### Finding 1 — CO-001: Default optimizer_runs for High-Frequency Protocol (MEDIUM)

**File:** foundry.toml, line 4
**Estimated impact:** 5–15% runtime gas reduction on swap functions

**Current foundry.toml:**
```toml
[profile.default]
optimizer = true
optimizer_runs = 200   # Foundry default — suboptimal for 10M calls/year
src = "src"
out = "out"
```

**Recommended foundry.toml:**
```toml
[profile.default]
optimizer = true
optimizer_runs = 1_000_000   # Maximizes runtime efficiency for high-frequency swap
src = "src"
out = "out"

[profile.script]
optimizer = true
optimizer_runs = 1            # Minimize deployment cost for one-shot deploy scripts
```

**Rationale:** `SwapRouter.swap()` is called an estimated 5M times per year.
At 1,000,000 optimizer_runs vs 200, empirical testing shows 8% per-call gas
reduction. At 5M calls and 150,000 gas/swap: 5M × 12,000 gas saved = 60B gas/year.

**Measurement:**
```bash
forge test --gas-report   # before: swap() = 145,230 gas
# apply optimizer_runs = 1_000_000
forge test --gas-report   # after: swap() = 133,012 gas  (saves 12,218 gas)
```

---

### Finding 2 — CO-002: via_ir Absent on Complex DeFi Protocol (MEDIUM)

**File:** foundry.toml, line 4
**Estimated impact:** 5–12% bytecode size reduction; faster hot paths

**Current foundry.toml:**
```toml
[profile.default]
optimizer = true
optimizer_runs = 1_000_000
# via_ir not set (defaults to false)
```

**Recommended foundry.toml:**
```toml
[profile.default]
optimizer = true
optimizer_runs = 1_000_000
via_ir = true       # Yul-level cross-function optimization

[profile.dev]
optimizer = true
optimizer_runs = 200
via_ir = false      # Faster compile for daily iteration
```

**Note:** `via_ir` increases compile time. Keep disabled in the dev profile.

---

### Finding 3 — CO-003: Outdated Pragma Missing Auto-Unchecked Loops (LOW)

**File:** src/SwapRouter.sol, line 2
**Estimated saving:** ~30 gas/loop iteration (auto-applied by compiler)

**Current:**
```solidity
pragma solidity ^0.8.0;   // Missing 4+ years of improvements
```

**Recommended:**
```solidity
pragma solidity 0.8.28;   // Latest stable — auto-unchecked loops, transient storage
```

**Action:** Bump pragma, run `forge test` to confirm no behavioral regressions,
verify against any security audit requirements for the specific compiler version.

---

## Summary

| Finding | Technique | Severity | Impact |
|---|---|---|---|
| optimizer_runs = 200 for AMM | CO-001 | MEDIUM | ~8% per-call runtime saving |
| via_ir disabled | CO-002 | MEDIUM | ~5–12% bytecode/runtime improvement |
| Outdated pragma | CO-003 | LOW | ~30 gas/loop iter, transient storage |
