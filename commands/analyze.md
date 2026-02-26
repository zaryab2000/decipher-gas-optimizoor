# /decipher-gas-optimizoor:analyze [path]

Conduct a full gas optimization analysis on a Foundry Solidity project.

## Arguments

- `[path]` — directory or file to analyze (default: `src/`)
- `--threshold <gas>` — suppress findings below this estimated gas saving (default: `100`)

## Workflow

### Step 1: Verify forge

Run:

```bash
forge --version
```

If the command fails or is not found, report:

> forge is not installed or not on PATH. Install Foundry: https://getfoundry.sh
> Analysis cannot proceed without forge.

Stop here.

### Step 2: Build

Run:

```bash
forge build
```

If the build fails, display the full compiler error output and stop. Do not proceed with
a broken build — findings on uncompiled code are unreliable.

### Step 3: Snapshot

Run:

```bash
forge snapshot
```

Save the full output. This establishes the gas baseline for every test function. If no
tests exist, note "No test snapshot available — findings are static analysis only" and
continue.

### Step 4: Storage layouts

For each `.sol` file under `[path]`:

1. Parse the file to extract all contract names declared with `contract`, `abstract
   contract`, or `library`.
2. For each contract name, run:

   ```bash
   forge inspect <ContractName> storageLayout --json
   ```

3. Parse the returned JSON. For each slot, note:
   - Which variables occupy it
   - How many bytes each variable consumes
   - Whether the slot has unused byte space (a packing gap)

Flag any slot where a smaller-type field is alone and another smaller-type field declared
nearby could have been packed alongside it.

### Step 5: Analyze

Apply all relevant gas optimization skills to identify issues. Each skill handles its
own domain — do not duplicate their detection logic here. Suppress any finding whose
estimated gas saving is below `--threshold`.

The active skills cover: storage-layout (SL-001–010), loop-optimization (LO-001–006),
calldata (CD-001–004), deployment (DP-001–004), type-optimization (TY-001–004),
custom-errors (CE-001–003), compiler-optimizer (CO-001–003),
immutable-and-constant (IC-001–003), unchecked-arithmetic (UA-001–002),
visibility (VI-001–002), event-logging (EV-001–002).

### Step 6: Output report

Produce the report using EXACTLY this format. Do not deviate from the table structure or
heading hierarchy.

```markdown
## Gas Analysis Report
**Target:** [path] | **Contracts:** [ContractA, ContractB, ...]

### Summary
| Severity | Count | Estimated Saving |
| -------- | ----- | ---------------- |
| Critical | N     | ~X gas           |
| High     | N     | ~X gas           |
| Medium   | N     | ~X gas           |
| Low      | N     | ~X gas           |

### Findings (sorted by gas saving, highest first)

#### [SEVERITY] [FINDING TITLE]
**File:** path/to/file.sol, line N
**Estimated saving:** ~X gas per call

**Current code:**
```solidity
[code]
```

**Optimized code:**
```solidity
[code]
```

**Why:** [one sentence — the EVM mechanic that makes the current code expensive]
```

Severity scale:
- **Critical** — >10,000 gas per call (e.g., eliminated storage slot, transient storage
  reentrancy guard)
- **High** — 1,000–10,000 gas per call (e.g., storage caching, struct packing)
- **Medium** — 100–1,000 gas per call (e.g., custom errors, calldata params)
- **Low** — <100 gas per call (e.g., unchecked loop counter, constant keccak)

Sort all findings within the report by estimated gas saving, highest first.

### Step 7: Action items

End every report with exactly this section:

```markdown
### Top 3 Actions

1. **[Highest-impact finding title]** — [file:line] — ~X gas saved per call.
   [One sentence on what to do.]

2. **[Second-highest-impact finding title]** — [file:line] — ~X gas saved per call.
   [One sentence on what to do.]

3. **[Third-highest-impact finding title]** — [file:line] — ~X gas saved per call.
   [One sentence on what to do.]
```

If fewer than 3 findings exist, list all of them.

## Example Finding

#### HIGH: Storage variable read in loop without cache
**File:** src/Staking.sol, line 42
**Estimated saving:** ~2,000 gas per loop iteration (97 gas/warm SLOAD avoided × N iterations)

**Current code:**
```solidity
for (uint256 i = 0; i < stakes.length; i++) {
    total += stakes[i] * rewardRate; // rewardRate: SLOAD every iteration
}
```

**Optimized code:**
```solidity
uint256 _rewardRate = rewardRate; // cache once: 1 SLOAD
for (uint256 i = 0; i < stakes.length; i++) {
    total += stakes[i] * _rewardRate; // MLOAD: 3 gas
}
```

**Why:** After the first SLOAD, subsequent reads to `rewardRate` cost 100 gas (warm
SLOAD) vs 3 gas (MLOAD); caching before the loop replaces N warm SLOADs with N MLOADs,
saving 97 gas × N iterations.
