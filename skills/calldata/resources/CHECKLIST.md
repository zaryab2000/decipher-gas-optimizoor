# Calldata Skill — Pre-completion Checklist

Run this before marking a calldata review complete.

## CD-001 and CD-002: external function reference parameters

- [ ] All `external` functions identified and listed
- [ ] Every `memory` array, `bytes`, `string`, or struct parameter checked for
  read-only vs write access
- [ ] `calldata` applied to all read-only reference parameters
- [ ] Internal helpers that receive calldata parameters updated to `calldata` too
- [ ] `public` functions that need calldata: VI-001 applied first (change to `external`)
- [ ] Compilation passes with no type errors after changes

## CD-003: small-type parameters

- [ ] All `uint8`, `uint16`, `uint32`, `uint64` parameters and local variables checked
- [ ] Confirmed: are they used in arithmetic outside a packed struct?
- [ ] Changed to `uint256` where not in a packed storage struct
- [ ] Interface compatibility verified (ERC standards, imported interfaces)

## CD-004: boolean bitmap

- [ ] Functions with 3+ `bool` parameters identified
- [ ] Bitmap encoding applied with documented `constant` bit positions
- [ ] Existing callers updated to use bitmap encoding
- [ ] ABI/frontend impact assessed (breaking change for external callers)

## Verification

- [ ] `forge test` passes with no errors or regressions
- [ ] `forge test --gas-report` shows reduced gas for changed functions
- [ ] `forge snapshot --diff` confirms measurable saving (not zero)
