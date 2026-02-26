# /decipher-gas-optimizoor:compare [ref1] [ref2]

Compare gas snapshots between two git references to identify regressions and improvements.

## Arguments

- `[ref1]` — base git reference (default: `HEAD~1`)
- `[ref2]` — target git reference (default: `HEAD`)

## Workflow

### Step 1: Verify forge and git

Run:

```bash
forge --version
git --version
```

If either command fails, report the missing tool and its install URL, then stop:

- forge: https://getfoundry.sh
- git: https://git-scm.com

### Step 2: Check for uncommitted changes

Run:

```bash
git status --porcelain
```

If the output is non-empty, warn:

> Warning: working tree has uncommitted changes. These will be stashed before
> checkout and restored afterward. Any stash conflicts must be resolved manually.

### Step 3: Stash uncommitted changes

Only if Step 2 found a dirty working tree, run:

```bash
git stash
```

Record whether a stash was created (true/false) for use in Step 6.

### Step 4: Snapshot ref1

Run:

```bash
git checkout [ref1]
forge snapshot --snap /tmp/gas-snapshot-ref1.txt
```

If `forge snapshot` fails (e.g., build error on ref1), report the error, restore working
state (Step 6 cleanup), and stop.

### Step 5: Snapshot ref2

Run:

```bash
git checkout [ref2]
forge snapshot --snap /tmp/gas-snapshot-ref2.txt
```

If `forge snapshot` fails on ref2, report the error, restore working state, and stop.

### Step 6: Restore original state

Run in sequence:

```bash
git checkout -
```

If a stash was created in Step 3, then run:

```bash
git stash pop
```

If `git stash pop` fails due to a conflict, warn the user:

> Warning: git stash pop failed due to merge conflict. Your stashed changes are still
> in the stash. Run `git stash show` to inspect and `git stash pop` to retry manually.

Continue to Step 7 regardless — the comparison data is already collected.

### Step 7: Parse snapshots and compute deltas

Read both snapshot files. Each line has the format:

```
ContractName:functionName() gas: 12345
```

Build a map of `contract:function -> gas` for each snapshot. Then for every function
that appears in both snapshots:

```
delta     = ref2_gas - ref1_gas
delta_pct = (delta / ref1_gas) * 100
```

Classify each function:
- `delta > 0` → regression
- `delta < 0` → improvement
- `delta == 0` → unchanged (omit from output)

Functions present in ref2 but not ref1 are new additions — note them separately.
Functions present in ref1 but not ref2 are removed — note them separately.

### Step 8: Output comparison table

Produce the report using EXACTLY this format:

```markdown
## Gas Comparison: [ref1] -> [ref2]

### [ContractName]
| Function    | [ref1] | [ref2] | Delta  | %      |
| ----------- | ------ | ------ | ------ | ------ |
| functionA() | 45,230 | 38,400 | -6,830 | -15.1% |
| functionB() | 12,100 | 13,500 | +1,400 | +11.6% |

### Summary
- Regressions: N functions | Improvements: N functions | Net: +/-X gas

### Regressions
- ContractName:functionB() +1,400 gas (+11.6%)
- [sorted by delta descending — worst regressions first]

### Improvements
- ContractName:functionA() -6,830 gas (-15.1%)
- [sorted by delta ascending — biggest wins first]

### New functions (in [ref2] only)
- ContractName:newFunc() — 9,200 gas (no baseline)

### Removed functions (in [ref1] only)
- ContractName:oldFunc() — was 7,500 gas
```

Format all gas numbers with comma separators (e.g., `45,230`). Format deltas with
explicit `+` or `-` sign. Format percentages to one decimal place.

If there are no regressions, omit the Regressions section. If there are no improvements,
omit the Improvements section.

### Step 9: Cleanup

Run:

```bash
rm -f /tmp/gas-snapshot-ref1.txt /tmp/gas-snapshot-ref2.txt
```

## Example Output

```markdown
## Gas Comparison: HEAD~1 -> HEAD

### TokenVault
| Function      | HEAD~1 | HEAD   | Delta  | %      |
| ------------- | ------ | ------ | ------ | ------ |
| deposit()     | 45,230 | 38,400 | -6,830 | -15.1% |
| withdraw()    | 32,100 | 32,100 |      0 |   0.0% |
| claimReward() | 18,500 | 19,900 | +1,400 |  +7.6% |

### Summary
- Regressions: 1 function | Improvements: 1 function | Net: -5,430 gas

### Regressions
- TokenVault:claimReward() +1,400 gas (+7.6%)

### Improvements
- TokenVault:deposit() -6,830 gas (-15.1%)
```
