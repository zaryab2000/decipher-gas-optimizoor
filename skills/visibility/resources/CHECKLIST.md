# Visibility Review Checklist

Run before marking any visibility review complete.

- [ ] Every `public` function searched for internal callers (bare `fnName(` calls in same contract)
- [ ] All confirmed-external-only functions changed to `external` (VI-001)
- [ ] Reference-type params (`array`, `bytes`, `string`, `struct`) on `external` functions use `calldata` (CD-001/CD-002)
- [ ] Manual getter functions that duplicate auto-generated getters removed (VI-002)
- [ ] Functions called via `this.fnName()` kept as `public`
- [ ] Interface-required visibility preserved
- [ ] `rg "fnName\(" --type sol` run for each changed function to confirm no missed callers
- [ ] `forge test` passes after changes
