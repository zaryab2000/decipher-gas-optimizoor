# /gas:baseline

Read, update, or query the `.gas-snapshot` file produced by `forge snapshot`.

## Arguments

- _(no args)_ — display a summary table of the current baseline
- `--update` — rebuild the baseline by running `forge build` + `forge snapshot`
- `--show <X>` — filter the baseline to lines matching contract name or function name `X`

---

## Mode 1: No arguments (show summary)

Read `.gas-snapshot` in the current working directory.

If the file does not exist, output:

> No gas baseline found. Run `/gas:baseline --update` to create one.

If the file exists, parse every line. Each line has the format:

```
ContractName:functionName() gas: 12345
```

Output a summary table using EXACTLY this format:

```markdown
## Gas Baseline Summary
**File:** .gas-snapshot | **Functions recorded:** N

| Contract | Function | Gas |
| -------- | -------- | --- |
| TokenVault | deposit() | 38,400 |
| TokenVault | withdraw() | 32,100 |
| StakingPool | stake() | 55,200 |
```

Sort rows by contract name alphabetically, then by function name alphabetically within
each contract. Format gas values with comma separators.

End with:

> Total: N functions across M contracts.

---

## Mode 2: --update

Run in sequence:

```bash
forge build
```

If build fails, display errors and stop. Do not proceed to snapshot with a broken build.

```bash
forge snapshot
```

After completion, count the lines in `.gas-snapshot` to determine N.

Output:

> Gas baseline updated: N functions recorded in .gas-snapshot
>
> Commit the baseline to version control:
>   git add .gas-snapshot && git commit -m "chore: update gas baseline"

---

## Mode 3: --show X

Read `.gas-snapshot`. Filter lines where the line text contains `X` (case-insensitive
substring match against both the contract name portion and the function name portion).

If no lines match, output:

> No entries found matching "[X]" in .gas-snapshot

If lines match, output them in table format:

```markdown
## Gas Baseline: entries matching "[X]"

| Contract | Function | Gas |
| -------- | -------- | --- |
| TokenVault | deposit() | 38,400 |
```

Include a count at the end:

> N entries matched.

---

## Error handling

- If `.gas-snapshot` exists but is empty: report "Gas snapshot file is empty. Run
  `/gas:baseline --update` to populate it."
- If forge is not on PATH (for `--update` only): report install URL
  (https://getfoundry.sh) and stop.
- Never create or write `.gas-snapshot` directly — only `forge snapshot` may write it.
