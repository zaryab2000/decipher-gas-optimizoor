# Type Optimization — Example Finding

## Contract Under Review

`ProtocolConfig.sol` — a protocol contract with uint8 loop counters, 4
standalone bool flags, and a string symbol.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

contract ProtocolConfig {

    // Issue 1 (TY-003): 4 standalone bools — 4 storage slots
    bool public paused;
    bool public depositsEnabled;
    bool public withdrawalsEnabled;
    bool public feesEnabled;

    // Issue 2 (TY-002): string for a fixed short identifier
    string public symbol;

    address public immutable OWNER;

    constructor(address owner) {
        OWNER   = owner;
        symbol  = "PROT";          // short fixed string — fits in bytes32
        paused  = false;
        depositsEnabled    = true;
        withdrawalsEnabled = true;
        feesEnabled        = false;
    }

    // Issue 3 (TY-001): uint8 loop counter in a batch operation
    function processAddresses(address[] calldata addrs) external {
        for (uint8 i = 0; i < addrs.length; ++i) {
            _process(addrs[i]);
        }
    }

    function _process(address addr) internal {}
}
```

## Finding 1 — TY-003: 4 standalone bool state variables

**File:** `ProtocolConfig.sol:7–10`
**Severity:** high
**Gas saved:**
- 3 storage slots eliminated
- Cold write savings: 3 × 22,100 = **66,300 gas**
- Cold read savings: 3 × 2,100 = **6,300 gas** per full co-read

Each `bool` occupies its own 32-byte storage slot. A `uint256` bitmap stores
all 4 flags in a single slot, eliminating 3 cold SSTOREs on first write.

**Before:**
```solidity
bool public paused;               // slot 0
bool public depositsEnabled;      // slot 1
bool public withdrawalsEnabled;   // slot 2
bool public feesEnabled;          // slot 3
```

**After:**
```solidity
uint256 private constant FLAG_PAUSED               = 1;   // bit 0
uint256 private constant FLAG_DEPOSITS_ENABLED     = 2;   // bit 1
uint256 private constant FLAG_WITHDRAWALS_ENABLED  = 4;   // bit 2
uint256 private constant FLAG_FEES_ENABLED         = 8;   // bit 3

uint256 private _flags = FLAG_DEPOSITS_ENABLED | FLAG_WITHDRAWALS_ENABLED;

function isPaused()              external view returns (bool) {
    return _flags & FLAG_PAUSED != 0;
}
function areDepositsEnabled()    external view returns (bool) {
    return _flags & FLAG_DEPOSITS_ENABLED != 0;
}
function areWithdrawalsEnabled() external view returns (bool) {
    return _flags & FLAG_WITHDRAWALS_ENABLED != 0;
}
function areFeesEnabled()        external view returns (bool) {
    return _flags & FLAG_FEES_ENABLED != 0;
}
function pause()   external { _flags |= FLAG_PAUSED; }
function unpause() external { _flags &= ~FLAG_PAUSED; }
```

**Verification:**
```bash
forge inspect ProtocolConfig storageLayout --json   # 1 slot not 4
forge snapshot --diff
```

## Finding 2 — TY-002: string symbol should be bytes32

**File:** `ProtocolConfig.sol:13`
**Severity:** medium
**Gas saved:**
- ~22,100 gas deployment (storage slot eliminated when changed to `constant`)
- ~500 gas per non-constant write
- Zero runtime SLOADs when declared `constant`

"PROT" is 4 bytes — safely fits in `bytes32` with no truncation risk.

**Before:**
```solidity
string public symbol;
// constructor: symbol = "PROT";
```

**After:**
```solidity
bytes32 public constant SYMBOL = "PROT";

// If ERC-20 string interface compatibility is needed:
function symbol() external pure returns (string memory) {
    return string(abi.encodePacked(SYMBOL));
}
```

**Verification:**
```bash
forge inspect ProtocolConfig storageLayout --json   # no slot for SYMBOL
forge test --gas-report
```

## Finding 3 — TY-001: uint8 loop counter

**File:** `ProtocolConfig.sol:30`
**Severity:** low
**Gas saved:** ~10–22 gas per loop iteration (AND 0xFF masking eliminated)

`i` is a loop counter never stored in a packed struct. `uint8` triggers an
AND mask after each `++i` (enforcing 8-bit range). `uint256` is the EVM
native word — no masking needed.

**Before:**
```solidity
for (uint8 i = 0; i < addrs.length; ++i) {
```

**After:**
```solidity
for (uint256 i = 0; i < addrs.length; ++i) {
```

**Note:** Solidity 0.8.22+ auto-unchecks simple loop counters — the overflow
check on `++i` is already removed by the compiler. The remaining saving is
the AND masking on the counter arithmetic itself.

**Verification:**
```bash
forge snapshot --diff
forge test --match-test testProcessAddresses -vvvv   # no AND 0xFF in trace
```

## Summary

| Finding | Location | Gas Impact |
|---|---|---|
| TY-003: bool → uint256 bitmap | lines 7–10 | ~66,300 gas (3 cold SSTORE) |
| TY-002: string → bytes32 | line 13 | ~22,100 gas deployment |
| TY-001: uint8 → uint256 counter | line 30 | ~10–22 gas/iteration |

All three findings together reduce both deployment cost and per-call runtime
gas with no behavioral changes. TY-003 has the highest impact and should be
applied first.
