# Unchecked Arithmetic Checklist

Run before marking any unchecked-arithmetic review complete.

- [ ] Every `unchecked {}` block has an `// INVARIANT:` comment explaining why it is safe
- [ ] Loop counter `unchecked { ++i; }` is inside the loop, not wrapping the body
- [ ] UA-002: the bounding `require`/`if+revert` is in the same function scope, not a caller
- [ ] No external calls occur between the bounds proof and the unchecked operation
- [ ] Business-critical arithmetic (balances, prices): fuzz test confirmed before applying
- [ ] Only the proven-safe operation is inside `unchecked {}` — nothing else
- [ ] `forge test` (with fuzz) passes after all unchecked changes
