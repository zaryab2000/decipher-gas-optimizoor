# Type Optimization Skill — Pre-completion Checklist

Run this before marking a type optimization review complete.

## TY-001: small types in computation

- [ ] All function parameters and local variables of type `uint8`, `uint16`,
  `uint32`, `uint64` identified
- [ ] Confirmed: are they in packed storage structs? (If yes → SL-001, not TY-001)
- [ ] Confirmed: are they required by an interface (ERC-20 `decimals()`, etc.)?
- [ ] Changed to `uint256` where not constrained by interface or storage packing
- [ ] Compilation passes with no type errors

## TY-002: string → bytes32

- [ ] All `string` state variables identified
- [ ] Confirmed: each string is ≤ 31 bytes and fixed (not variable-length)
- [ ] Changed to `bytes32 constant` or `bytes32 immutable` as appropriate
- [ ] If interface returns `string`: internal `bytes32` with conversion getter added
- [ ] `forge inspect <Contract> storageLayout --json` confirms fewer slots

## TY-003: bool bitmap

- [ ] Standalone `bool` state variable count checked (not bools inside structs)
- [ ] If 3 or more: `uint256` bitmap designed with named `constant` bit positions
- [ ] All bit positions documented with comments
- [ ] All read/write sites updated to use bitmask operations
- [ ] `forge inspect <Contract> storageLayout --json` confirms slot count reduced

## TY-004: unnecessary downcasts

- [ ] Downcasts in hot paths checked: `uint128(x)`, `uint64(x)`, etc.
- [ ] Confirmed: downcast is not required for storage into a packed struct
- [ ] Confirmed: downcast result is not required for interface compatibility
- [ ] Round-trip casts removed where applicable

## Verification

- [ ] `forge inspect <Contract> storageLayout --json` — slot counts verified
- [ ] `forge test --gas-report` — gas changes confirmed
- [ ] `forge snapshot --diff` — net saving is positive
- [ ] `forge test` — no regressions
