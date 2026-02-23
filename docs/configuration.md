# Configuration Reference

All configuration for `decipher-gas-optimizoor` is controlled through environment variables.
There are no config files to manage beyond the `.gas-snapshot` baseline itself.

---

## GAS_REGRESSION_THRESHOLD

**What it does:** Sets the gas unit threshold above which the regression guard hook emits a
warning. When a `.sol` file is saved, the hook runs `forge snapshot --diff` and compares the
delta for each test function against this threshold. Any function whose gas cost increased by
more than this amount triggers the regression output.

**Default:** `500`

**How to override:**

Set inline for a single command:
```bash
GAS_REGRESSION_THRESHOLD=200 forge test
```

Set for the current shell session:
```bash
export GAS_REGRESSION_THRESHOLD=200
```

Set persistently for all Claude Code sessions in this project via `.claude/settings.json`
(see the [Claude Code settings section](#setting-env-vars-via-claude-code-settings) below).

**When to change it:**

| Scenario | Recommended value |
| -------- | ----------------- |
| Production-critical DeFi contracts (every gas unit matters) | 100–200 |
| Standard contracts with stable test suite | 500 (default) |
| Active refactoring with a noisy test suite | 1,000–2,000 |
| Initial development before optimization pass | 2,000+ |

Lower thresholds catch more regressions but produce more noise during active development.
Higher thresholds reduce noise but may let meaningful regressions slip through unnoticed.
For contracts going to mainnet, lower is better — a 200-gas regression caught in development
costs nothing; the same regression on-chain costs real money at scale.

---

## GAS_SNAPSHOT_PATH

**What it does:** Specifies the path to the committed `.gas-snapshot` baseline file that the
regression guard hook compares against. The hook reads this file on every `.sol` save.

**Default:** `.gas-snapshot`

**How to override:**

```bash
export GAS_SNAPSHOT_PATH=packages/core/.gas-snapshot
```

**When to change it:**

The default works for single-package Foundry projects. Change it only when the snapshot file
is not at the project root — for example, in a monorepo where each package has its own
Foundry project:

```
monorepo/
  packages/
    core/
      foundry.toml
      .gas-snapshot   ← set GAS_SNAPSHOT_PATH=packages/core/.gas-snapshot
    periphery/
      foundry.toml
      .gas-snapshot   ← set GAS_SNAPSHOT_PATH=packages/periphery/.gas-snapshot
```

Each Claude Code session should be opened from the package root in this case, or the
`GAS_SNAPSHOT_PATH` must be set to an absolute path.

---

## optimizer_runs Tuning Guide

The `optimizer_runs` setting in `foundry.toml` controls the Solidity compiler's optimization
target. It is not an environment variable — it is a compiler setting — but it is the most
impactful single configuration change you can make for gas costs.

For the full analysis, see the compiler-optimizer skill: `skills/compiler-optimizer/SKILL.md`.

**Quick guide:**

| Value | Optimization target | Use when |
| ----- | ------------------- | -------- |
| `1` (minimum) | Minimize bytecode size | Factory contracts, deploy scripts, contracts deployed rarely |
| `200` (default) | Balanced size vs runtime | Most contracts; good starting point |
| `1,000,000` (maximum) | Minimize runtime gas | DeFi hot paths called thousands of times per day |

The value tells the optimizer how many times it expects each function to be called over the
contract's lifetime. Higher values make the optimizer work harder to reduce per-call gas at
the expense of larger bytecode.

**Setting in foundry.toml:**
```toml
[profile.default]
optimizer = true
optimizer_runs = 200

[profile.production]
optimizer = true
optimizer_runs = 1000000
```

Run with a specific profile:
```bash
FOUNDRY_PROFILE=production forge build
```

---

## Setting Env Vars via Claude Code Settings

Environment variables set in `.claude/settings.json` are applied to every Claude Code session
in that project. This is the recommended way to set project-specific defaults so you do not
have to remember to export them manually.

Create or edit `.claude/settings.json` in the project root:

```json
{
  "env": {
    "GAS_REGRESSION_THRESHOLD": "200",
    "GAS_SNAPSHOT_PATH": ".gas-snapshot"
  }
}
```

These values are read by the regression guard hook on every `.sol` save. The hook checks
`$GAS_REGRESSION_THRESHOLD` and `$GAS_SNAPSHOT_PATH` at runtime, so changes to
`settings.json` take effect immediately without restarting the Claude Code session.

**Note:** `.claude/settings.json` may contain project-specific configuration. Do not commit
sensitive values (API keys, private keys) to this file if the project is public. For this
plugin, both env vars are non-sensitive and safe to commit.
