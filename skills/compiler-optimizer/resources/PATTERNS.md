# Compiler Optimizer — Patterns Reference

## CO-001: optimizer_runs Tuning

### Pattern ID
`CO-001`

### Core concept
The `optimizer_runs` parameter is a hint to the Solidity optimizer: "this
code will be called approximately `runs` times." A low value minimizes
bytecode size (lower deployment cost at the expense of slightly higher
per-call runtime gas). A high value maximizes per-call runtime efficiency
at the expense of larger bytecode.

Deployment cost: 200 gas/byte of bytecode × bytecode size (one time).
Runtime cost: per-call gas × number of calls over contract lifetime.

The break-even calculation:
```
extra_deployment_bytes × 200 gas = per_call_savings × total_calls
```

For a DeFi AMM with 1,000,000 annual calls, a 50-gas/call saving breaks even
against 250,000 extra deployment bytes in a single year — and deployment is
one-time. High `runs` almost always wins for high-frequency contracts.

### Anti-pattern (foundry.toml)
```toml
# BAD: default runs=200 for a DeFi protocol with millions of calls per year
[profile.default]
optimizer = true
optimizer_runs = 200
```

### Optimized pattern (foundry.toml)
```toml
# Production profile — maximum runtime efficiency for high-frequency DeFi
[profile.default]
optimizer = true
optimizer_runs = 1_000_000

# Separate profile for factory/deployer scripts — minimize one-shot deployment cost
[profile.deploy]
optimizer = true
optimizer_runs = 1

# Development profile — balanced, fast compilation
[profile.dev]
optimizer = true
optimizer_runs = 200
```

### Decision table
| Contract type | optimizer_runs | Rationale |
|---|---|---|
| AMM router (Uniswap-style) | 1,000,000 | Called millions of times |
| Lending pool (Aave-style) | 1,000,000 | Hot path: borrow, repay, liquidate |
| Factory contract | 1 | Deploys instances, rarely called itself |
| Minimal proxy implementation | 1,000,000 | Code shared by all clones |
| General governance contract | 200 | Called infrequently |
| Test/script contracts | 200 | No production impact |

### Measurement
```bash
# Measure bytecode size at different runs values
FOUNDRY_PROFILE=default forge build --sizes
FOUNDRY_PROFILE=deploy  forge build --sizes

# Measure per-function gas at different runs values
forge test --gas-report
forge snapshot
```

---

## CO-002: via_ir (Yul Intermediate Representation)

### Pattern ID
`CO-002`

### Core concept
The classic Solidity compilation pipeline optimizes at the AST/ABI level,
within individual function scopes. The `via_ir` pipeline first lowers all
Solidity code to Yul (an intermediate language), then applies the Yul
optimizer — which operates across the entire compilation unit and can apply
cross-function optimizations, eliminate redundant memory operations, and
reduce stack pressure in ways the classic pipeline cannot.

Typical gains: 5–20% bytecode size reduction or runtime gas reduction on
complex contracts. Negligible impact on simple contracts.

### Anti-pattern (foundry.toml)
```toml
# BAD: via_ir disabled for a complex DeFi protocol
[profile.default]
optimizer = true
optimizer_runs = 200
# via_ir absent (defaults to false)
```

### Optimized pattern (foundry.toml)
```toml
# GOOD: via_ir enabled for production builds
[profile.default]
optimizer       = true
optimizer_runs  = 200
via_ir          = true    # Yul-level cross-function optimization

# Development profile: via_ir OFF for fast iteration (5–50× slower to compile)
[profile.dev]
optimizer      = true
optimizer_runs = 200
via_ir         = false
```

### When via_ir helps most
- Contracts with many internal function calls that the optimizer can inline
- Tight loops with complex bodies
- Heavy struct manipulation and memory operations
- Functions with many local variables (stack pressure relief)

### Tradeoffs
- Compile time: 5–50× slower than classic pipeline
- Correctness: more edge cases historically than classic pipeline — always
  run full test suite with `via_ir = true` before enabling in production
- Verification: deployment verification must use the same `via_ir` setting
  as the build that produced the deployed bytecode

---

## CO-003: Solidity Version for Built-in Optimizer Gains

### Pattern ID
`CO-003`

### Core concept
Each Solidity release includes optimizer improvements alongside bug fixes.
Key versions with material gas impact:

| Version | Built-in gain | Details |
|---|---|---|
| `0.8.22` | Auto-unchecked loop counters | Compiler detects when `i++` in a bounded loop cannot overflow and skips the SafeMath check automatically (~30 gas/iteration) |
| `0.8.24` | Native transient storage | `tstore`/`tload` syntax (no inline assembly required for EIP-1153) |
| `0.8.26` | Additional optimizer passes | Internal IR improvements |
| `0.8.28` | Latest stable | All cumulative improvements |

### Anti-pattern (Solidity file)
```solidity
// BAD: floating pragma — deploys on different compiler versions
pragma solidity ^0.8.0;

// BAD: old pinned version — missing years of optimizer improvements
pragma solidity 0.8.4;
```

### Optimized pattern (Solidity file)
```solidity
// GOOD: exact version pinned at latest stable
pragma solidity 0.8.28;
```

### Corresponding foundry.toml
```toml
[profile.default]
solc_version   = "0.8.28"
optimizer      = true
optimizer_runs = 200
via_ir         = true
```

### Version upgrade checklist
1. Bump `pragma solidity` in all `.sol` files
2. Update `solc_version` in `foundry.toml`
3. Run `forge build` — fix any compilation errors
4. Run `forge test` — confirm no behavioral regressions
5. Re-read Solidity release notes for breaking changes between old and new version
6. Re-run `forge test --gas-report` to measure gas delta
7. Update deployment verification settings to match new version

### Key behaviors to re-verify after version bump
- Arithmetic edge cases (overflow/underflow behavior in unchecked blocks)
- ABI encoding changes (check ABI-encoded outputs in tests)
- Custom error and event ABI compatibility with deployed interfaces
- Any assembly blocks using version-specific opcodes
