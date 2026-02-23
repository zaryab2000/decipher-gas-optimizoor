# Visibility Skill — Pre-completion Checklist

Run this before marking a visibility review complete.

## VI-001: public → external

- [ ] All `public` functions identified and listed
- [ ] Constructors, interface stubs, and state variable declarations excluded
- [ ] For each `public` function: searched full contract for bare internal calls
  (pattern: `functionName(` without `this.` prefix inside other function bodies)
- [ ] Functions with no internal call sites flagged as external candidates
- [ ] For each flagged function: changed `public` to `external`
- [ ] For each changed function with ref-type params: `memory` changed to `calldata`
  (CD-001 applied simultaneously for maximum impact)
- [ ] No `public` function incorrectly changed (e.g., called via `this.fn()`)

## VI-002: remove duplicate getters

- [ ] All `view` functions identified
- [ ] Checked for body pattern: `return stateVar` or `return mapping[param]`
- [ ] Confirmed: the underlying state variable is declared `public`
- [ ] Confirmed: the manual getter adds no logic (no access control, type
  conversion, computation, or interface-required naming difference)
- [ ] Duplicate getters deleted
- [ ] ABI consumers notified if function name changed (breaking change)

## Verification

- [ ] `forge build` — no compilation errors after visibility changes
- [ ] `forge test` — all tests pass (test contracts calling changed functions
  may need callsite updates if they used internal-call syntax)
- [ ] `forge test --gas-report` — reduced gas for changed functions confirmed
- [ ] `rg "functionName\(" --type sol` — confirm no remaining internal callers
  for functions changed to `external`
- [ ] `forge inspect <Contract> abi` — auto-generated getters still present for
  `public` state variables where manual getters were removed
