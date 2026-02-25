# Immutable and Constant Checklist

Run before marking any IC review complete.

- [ ] Every compile-time literal state variable is `constant` (IC-001)
- [ ] Every constructor-set-once state variable is `immutable` (IC-002)
- [ ] Variables read inside modifiers prioritized as IC-003 (highest severity)
- [ ] No `constant`/`immutable` applied to variables reassigned outside constructor
- [ ] No `immutable` applied to variables set in `initialize()` (upgradeable pattern)
- [ ] `forge snapshot --diff` run to confirm gas reduction
