# Immutable and Constant — Example Finding

## Contract Under Review

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract YieldVault {
    // --- Config constants stored as regular state variables ---
    uint256 public MAX_DEPOSIT      = 100_000 ether;   // compile-time known
    uint256 public WITHDRAWAL_FEE   = 50;              // basis points, compile-time
    uint256 public LOCK_DURATION    = 7 days;          // compile-time known

    // --- Addresses set in constructor, never changed ---
    address public owner;
    address public rewardToken;
    address public feeToken;
    address public treasury;
    address public priceOracle;

    // --- Mutable state ---
    mapping(address => uint256) public deposits;
    mapping(address => uint256) public depositTimestamp;
    uint256 public totalDeposited;

    constructor(
        address _owner,
        address _rewardToken,
        address _feeToken,
        address _treasury,
        address _priceOracle
    ) {
        owner        = _owner;
        rewardToken  = _rewardToken;
        feeToken     = _feeToken;
        treasury     = _treasury;
        priceOracle  = _priceOracle;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");   // SLOAD on every call
        _;
    }

    function deposit(uint256 amount) external {
        require(amount + totalDeposited <= MAX_DEPOSIT, "Cap exceeded");  // SLOAD
        require(amount > 0, "Zero amount");
        IERC20(feeToken).transferFrom(msg.sender, address(this), amount); // SLOAD feeToken
        deposits[msg.sender]         += amount;
        depositTimestamp[msg.sender]  = block.timestamp;
        totalDeposited               += amount;
    }

    function withdraw(uint256 amount) external {
        uint256 ts = depositTimestamp[msg.sender];
        require(block.timestamp >= ts + LOCK_DURATION, "Locked");  // SLOAD
        uint256 fee        = (amount * WITHDRAWAL_FEE) / 10_000;   // SLOAD
        uint256 net        = amount - fee;
        deposits[msg.sender] -= amount;
        totalDeposited       -= amount;
        IERC20(feeToken).transfer(treasury, fee);  // SLOAD feeToken + SLOAD treasury
        IERC20(feeToken).transfer(msg.sender, net); // SLOAD feeToken (again)
    }

    function setRewardRate(uint256 rate) external onlyOwner {  // SLOAD owner
        // update reward logic
    }

    function pause() external onlyOwner {  // SLOAD owner
        // pause logic
    }

    function getOraclePrice() public view returns (uint256) {
        return IPriceOracle(priceOracle).getPrice();  // SLOAD priceOracle
    }
}

interface IPriceOracle {
    function getPrice() external view returns (uint256);
}
```

---

## Analysis

**IC-001 candidates (compile-time constants stored as regular variables):** 3
**IC-002/IC-003 candidates (constructor-set values stored as regular variables):** 5
**Total storage slots that can be eliminated:** 8
**Estimated deployment gas saved:** ~176,800 gas (8 × 22,100 gas cold SSTORE)
**Estimated per-call savings:** varies by function — see findings below

---

## Findings

### [HIGH] IC-001 — Three compile-time literals stored in regular storage

**File:** src/YieldVault.sol, lines 7–9
**Estimated saving per read:** ~2,097 gas (cold SLOAD eliminated per variable per tx)

`MAX_DEPOSIT`, `WITHDRAWAL_FEE`, and `LOCK_DURATION` are literal values known at
compile time. They occupy storage slots unnecessarily.

```solidity
// BEFORE — 3 storage slots; SLOADs in deposit() and withdraw()
uint256 public MAX_DEPOSIT    = 100_000 ether;
uint256 public WITHDRAWAL_FEE = 50;
uint256 public LOCK_DURATION  = 7 days;

// AFTER — 0 storage slots; values inlined as bytecode literals
uint256 public constant MAX_DEPOSIT    = 100_000 ether;
uint256 public constant WITHDRAWAL_FEE = 50;
uint256 public constant LOCK_DURATION  = 7 days;
```

**Savings calculation:**
- `MAX_DEPOSIT`: read in every `deposit()` call — 2,097 gas saved per cold read
- `WITHDRAWAL_FEE`: read in every `withdraw()` call — 2,097 gas saved per cold read
- `LOCK_DURATION`: read in every `withdraw()` call — 2,097 gas saved per cold read
- Deployment: 3 × 22,100 gas SSTORE eliminated = **66,300 gas saved at deployment**

---

### [HIGH] IC-003 — owner address stored in regular storage; read on every onlyOwner call

**File:** src/YieldVault.sol, line 12
**Estimated saving:** ~2,097 gas per `onlyOwner`-guarded function call

`owner` is set in the constructor and never reassigned. It is read in the `onlyOwner`
modifier, which guards `setRewardRate` and `pause`. Every call to either function pays
a cold SLOAD (2,100 gas) on first access per transaction.

```solidity
// BEFORE — SLOAD on every guarded call
address public owner;

modifier onlyOwner() {
    require(msg.sender == owner);   // 2,100 gas cold SLOAD
    _;
}

// AFTER — PUSH20 on every guarded call (~3 gas)
address public immutable OWNER;

modifier onlyOwner() {
    require(msg.sender == OWNER);   // ~3 gas — value in bytecode
    _;
}
```

**Savings calculation:**
- Each call to `setRewardRate` or `pause`: **2,097 gas saved** per call
- Deployment: 1 × 22,100 gas SSTORE eliminated
- Example: 100 admin calls/day × 2,097 gas = **209,700 gas saved per day**

---

### [HIGH] IC-003 — feeToken address stored in regular storage; read 3× in withdraw()

**File:** src/YieldVault.sol, line 14
**Estimated saving:** ~2,097 gas on first read per tx + ~97 gas per warm re-read

`feeToken` is read three times in `withdraw()` (once in `deposit()` and twice more in
`withdraw()`) and never reassigned.

```solidity
// BEFORE — first read: 2,100 gas cold SLOAD; subsequent warm reads: 100 gas each
address public feeToken;

// In withdraw():
IERC20(feeToken).transfer(treasury, fee);   // SLOAD #1 (cold, 2,100 gas)
IERC20(feeToken).transfer(msg.sender, net); // SLOAD #2 (warm, 100 gas)

// AFTER — all reads: PUSH20 (~3 gas)
address public immutable FEE_TOKEN;
```

---

### [HIGH] IC-002 — treasury, rewardToken, priceOracle stored in regular storage

**File:** src/YieldVault.sol, lines 13, 15, 16
**Estimated saving:** ~2,097 gas per read (cold) per variable

Three more constructor-set addresses that are read in hot paths:
- `treasury`: read in `withdraw()` for fee transfer target
- `rewardToken`: read in reward distribution logic
- `priceOracle`: read in `getOraclePrice()`, which may be called frequently

```solidity
// BEFORE — each address costs a cold SLOAD on first use per tx
address public rewardToken;
address public treasury;
address public priceOracle;

// AFTER — all embedded in bytecode
address public immutable REWARD_TOKEN;
address public immutable TREASURY;
address public immutable PRICE_ORACLE;
```

---

## Optimized Contract

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract YieldVault {
    // --- Compile-time constants (IC-001) — zero runtime read cost ---
    uint256 public constant MAX_DEPOSIT    = 100_000 ether;
    uint256 public constant WITHDRAWAL_FEE = 50;            // basis points
    uint256 public constant LOCK_DURATION  = 7 days;

    // --- Constructor-set addresses (IC-002/IC-003) — ~3 gas per read ---
    address public immutable OWNER;
    address public immutable REWARD_TOKEN;
    address public immutable FEE_TOKEN;
    address public immutable TREASURY;
    address public immutable PRICE_ORACLE;

    // --- Mutable state ---
    mapping(address => uint256) public deposits;
    mapping(address => uint256) public depositTimestamp;
    uint256 public totalDeposited;

    constructor(
        address owner,
        address rewardToken,
        address feeToken,
        address treasury,
        address priceOracle
    ) {
        OWNER        = owner;
        REWARD_TOKEN = rewardToken;
        FEE_TOKEN    = feeToken;
        TREASURY     = treasury;
        PRICE_ORACLE = priceOracle;
    }

    modifier onlyOwner() {
        require(msg.sender == OWNER);  // PUSH20 (~3 gas) — no SLOAD
        _;
    }

    function deposit(uint256 amount) external {
        require(amount + totalDeposited <= MAX_DEPOSIT, "Cap exceeded");  // inlined literal
        require(amount > 0, "Zero amount");
        IERC20(FEE_TOKEN).transferFrom(msg.sender, address(this), amount);
        deposits[msg.sender]         += amount;
        depositTimestamp[msg.sender]  = block.timestamp;
        totalDeposited               += amount;
    }

    function withdraw(uint256 amount) external {
        uint256 ts = depositTimestamp[msg.sender];
        require(block.timestamp >= ts + LOCK_DURATION, "Locked");  // inlined literal
        uint256 fee = (amount * WITHDRAWAL_FEE) / 10_000;          // inlined literal
        uint256 net = amount - fee;
        deposits[msg.sender] -= amount;
        totalDeposited       -= amount;
        IERC20(FEE_TOKEN).transfer(TREASURY, fee);    // PUSH20s — no SLOADs
        IERC20(FEE_TOKEN).transfer(msg.sender, net);
    }

    function setRewardRate(uint256 rate) external onlyOwner {
        // update reward logic
    }

    function pause() external onlyOwner {
        // pause logic
    }

    function getOraclePrice() public view returns (uint256) {
        return IPriceOracle(PRICE_ORACLE).getPrice();  // PUSH20 — no SLOAD
    }
}

interface IPriceOracle {
    function getPrice() external view returns (uint256);
}
```

## Total Gas Savings Summary

| Finding | Deployment saving | Per-call saving |
|---------|-------------------|-----------------|
| IC-001: MAX_DEPOSIT (constant) | ~22,100 gas | ~2,097 gas/cold read in deposit() |
| IC-001: WITHDRAWAL_FEE (constant) | ~22,100 gas | ~2,097 gas/cold read in withdraw() |
| IC-001: LOCK_DURATION (constant) | ~22,100 gas | ~2,097 gas/cold read in withdraw() |
| IC-003: OWNER (immutable) | ~22,100 gas | ~2,097 gas per onlyOwner call |
| IC-002: REWARD_TOKEN (immutable) | ~22,100 gas | ~2,097 gas/cold read |
| IC-003: FEE_TOKEN (immutable) | ~22,100 gas | ~2,097 gas per deposit(); ~2,097 + ~97 in withdraw() |
| IC-002: TREASURY (immutable) | ~22,100 gas | ~2,097 gas/cold read in withdraw() |
| IC-002: PRICE_ORACLE (immutable) | ~22,100 gas | ~2,097 gas per getOraclePrice() call |
| **Total** | **~176,800 gas at deployment** | **~2,097 gas saved per hot-path read** |

Note: "per-call" savings are for the cold (first-in-transaction) SLOAD case. Warm SLOADs
(100 gas) save ~97 gas each when replaced by PUSH (~3 gas).

## Verification

```bash
forge inspect YieldVault storageLayout --json     # confirm 0 slots for immutable/constant vars
forge test --gas-report                           # compare per-function gas before/after
forge snapshot --diff                             # measure total test suite gas delta
```
