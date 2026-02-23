# Custom Errors — Patterns Reference

## Pattern: CE-001 — require with string message → custom error

**Anti-pattern (costs ~24 gas extra per revert + bytecode inflation):**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Ownable {
    address public owner;

    function setOwner(address newOwner) external {
        require(msg.sender == owner, "Only owner");
        owner = newOwner;
    }

    function pause() external {
        require(msg.sender == owner, "Only owner");  // string stored twice in bytecode
    }
}
```

**Optimized (saves ~15–50 gas per revert, bytecode reduced):**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Ownable {
    error NotOwner();  // declared once — 4-byte selector reused everywhere

    address public owner;

    function setOwner(address newOwner) external {
        if (msg.sender != owner) revert NotOwner();
        owner = newOwner;
    }

    function pause() external {
        if (msg.sender != owner) revert NotOwner();  // same selector, no extra bytecode
    }
}
```

**The EVM mechanic:** `require(cond, "string")` ABI-encodes the error string as
`Error(string)` return data: 4-byte selector + 32-byte offset + 32-byte length +
ceil(len/32) × 32 bytes of string data. A 10-byte string ("Only owner") pads to 96
bytes of revert data. A custom error encodes only 4 bytes.

**When this applies:** Every `require` call with a string literal second argument in
a contract targeting Solidity 0.8.4+.

**When it doesn't apply:** `require(condition)` with no string — nothing to convert.
Also: Solidity < 0.8.4 (custom errors unavailable), or library code you cannot modify.

---

## Pattern: CE-002 — bare revert("string") → custom error

**Anti-pattern (costs ~15–50 gas extra per revert + bytecode inflation):**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract PaymentRouter {
    function route(address to, uint256 amount) external {
        if (to == address(0)) revert("Zero address");     // BAD: string revert
        if (amount == 0)      revert("Zero amount");       // BAD: string revert
        if (amount > 1 ether) revert("Exceeds limit");     // BAD: string revert
        payable(to).transfer(amount);
    }
}
```

**Optimized (saves ~15–50 gas per revert; bytecode reduced per string removed):**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract PaymentRouter {
    error ZeroAddress();
    error ZeroAmount();
    error ExceedsLimit();

    function route(address to, uint256 amount) external {
        if (to == address(0)) revert ZeroAddress();    // 4-byte selector only
        if (amount == 0)      revert ZeroAmount();
        if (amount > 1 ether) revert ExceedsLimit();
        payable(to).transfer(amount);
    }
}
```

**The EVM mechanic:** Identical to CE-001 — `revert("string")` is syntactic sugar for
`require(false, "string")`. The string is stored in bytecode and ABI-encoded on every
revert. Each string removed reduces deployment cost by approximately 200 gas per byte.

**When this applies:** Any `revert("string literal")` in function bodies.

**When it doesn't apply:** `revert()` with no argument (already zero-cost bare revert).
`revert CustomError()` — already correct.

---

## Pattern: CE-003 — parameterless custom error → typed parameters

**Anti-pattern (loses debugging context; no string cost benefit here — already a custom error):**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract TokenVault {
    error InsufficientBalance;  // no context — what was needed vs available?

    mapping(address => uint256) public balances;

    function withdraw(uint256 amount) external {
        if (balances[msg.sender] < amount) revert InsufficientBalance();
        // caller cannot determine needed vs available from this revert
    }
}
```

**Optimized (adds typed context; ABI-decodable by Ethers.js v6, Viem, Tenderly):**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract TokenVault {
    error InsufficientBalance(uint256 needed, uint256 available);

    mapping(address => uint256) public balances;

    function withdraw(uint256 amount) external {
        uint256 balance = balances[msg.sender];
        if (balance < amount) revert InsufficientBalance(amount, balance);
        // caller sees exactly how much was needed and how much was available
    }
}
```

**The EVM mechanic:** Custom error parameters are ABI-encoded as typed values (32 bytes
per parameter) in revert data. Two `uint256` parameters add 64 bytes — still far smaller
than an equivalent string revert with interpolated values. The result is structured,
decodable, and compact.

**When this applies:** A custom error fires at a site where useful runtime values exist
(amounts, indices, addresses) that would help the caller understand or handle the revert.

**When it doesn't apply:**
- `NotOwner()` — `msg.sender` is already known to the caller; no typed context needed
- Errors in privacy-sensitive contexts where internal state should not be exposed
- Errors with no meaningful runtime context (e.g., `Paused()`, `Locked()`)
