# Loop Optimization Checklist

Run before marking any loop review complete.

- [ ] Array `.length` in loop condition is cached to a local `uint256` (LO-001)
- [ ] Every loop-invariant storage variable is cached before the loop (LO-002)
- [ ] Loop counter increment is wrapped in `unchecked {}` with `++i` (LO-003 + LO-004)
- [ ] Cached `.length` is NOT from an array the loop body pushes to or pops from
- [ ] Cached storage var is NOT written inside the loop body
- [ ] `&&` conditions ordered cheapest-first to maximize short-circuit (LO-006)
- [ ] `forge snapshot --diff` run to confirm gas reduction
