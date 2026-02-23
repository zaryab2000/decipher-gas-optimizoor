# Deployment — Patterns Reference

## DP-001: ERC-1167 Minimal Proxy Factory

### Pattern ID
`DP-001`

### Core concept
Deploying a full contract for each user in a factory pattern pays 32,000 gas
(CREATE) + 200 gas/byte of bytecode per instance. A 2,500-byte contract costs
~532,000 gas per deployment. An ERC-1167 minimal proxy is exactly 45 bytes:
32,000 + 200 × 45 = 41,000 gas. All proxies share one implementation contract
deployed once. Each proxy DELEGATECALL to the implementation with its own
isolated storage.

### Deployment cost math
```
Full contract (2,500 bytes): 32,000 + 200 × 2,500 = 532,000 gas
ERC-1167 proxy (45 bytes):   32,000 + 200 × 45   =  41,000 gas
Savings per clone:           491,000 gas
Savings at 100 clones:       49,100,000 gas
```

### Anti-pattern
```solidity
contract VaultFactory {
    function createVault() external returns (address) {
        // BAD: deploys full Vault bytecode per user
        Vault vault = new Vault(msg.sender);
        return address(vault);
    }
}

contract Vault {
    address public owner;
    constructor(address _owner) { owner = _owner; }
    // ... 2,500+ bytes of functions ...
}
```

### Optimized pattern
```solidity
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract VaultFactory {
    address public immutable IMPLEMENTATION;

    constructor() {
        // Deploy implementation once — full cost paid once
        IMPLEMENTATION = address(new VaultImpl());
    }

    function createVault() external returns (address) {
        // Deploy 45-byte proxy per user — ~41,000 gas each
        address clone = Clones.clone(IMPLEMENTATION);
        VaultImpl(clone).initialize(msg.sender);
        return clone;
    }
}

contract VaultImpl {
    address public owner;
    bool private _initialized;

    constructor() {
        // Prevent direct initialization of the implementation contract
        _initialized = true;
    }

    function initialize(address _owner) external {
        require(!_initialized, "Already initialized");
        _initialized = true;
        owner = _owner;
    }
    // ... same functions as Vault ...
}
```

### OpenZeppelin alternative (recommended)
```solidity
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract VaultImpl is Initializable {
    address public owner;

    constructor() {
        _disableInitializers();   // prevents initialization of implementation
    }

    function initialize(address _owner) external initializer {
        owner = _owner;
    }
}
```

### When NOT to apply
- Instances need different bytecode (logic differs, not just state): clones
  share code — use full deployment when behavior genuinely varies per instance.
- Per-call DELEGATECALL overhead (~100 gas warm) is unacceptable for extremely
  gas-sensitive functions.
- Upgradeable clones are needed: use ERC-1967 beacon proxies instead.

---

## DP-002: payable Admin Functions

### Pattern ID
`DP-002`

### Core concept
Non-`payable` functions include an automatic Solidity guard: if `msg.value > 0`,
revert. This guard compiles to CALLVALUE + ISZERO + JUMPI — approximately
24 gas. Marking a function `payable` removes this guard. For admin functions
called thousands of times in high-frequency protocols, the saving compounds.

### Cost math
- CALLVALUE:  2 gas
- ISZERO:     3 gas
- JUMPI:      10 gas + branching overhead
- Total overhead per non-payable call: ~24 gas

### Anti-pattern
```solidity
// Non-payable: Solidity inserts MSG.VALUE == 0 check
function setFeeRate(uint256 rate) external onlyAdmin {
    feeRate = rate;
}
```

### Optimized pattern
```solidity
// payable: ETH check removed (~24 gas saved per call)
function setFeeRate(uint256 rate) external payable onlyAdmin {
    feeRate = rate;
}
```

### Safety requirements
- The contract must either have a withdrawal mechanism for accidentally sent
  ETH, or the admin role must be held by a smart wallet/multisig that would
  never accidentally send ETH.
- Never apply to user-facing functions: `payable` signals to callers that ETH
  is expected, misleading users.
- This is the lowest-priority optimization — apply only after storage, loop,
  calldata, and type optimizations are complete.

---

## DP-003: Dead Code Removal

### Pattern ID
`DP-003`

### Core concept
Deployed bytecode costs 200 gas/byte. Dead code — unreachable branches,
constant-false conditions, unused internal/private functions — still compiles
into bytecode unless explicitly removed or provably unreachable. The optimizer
eliminates some dead code automatically, but complex patterns require explicit
removal.

### Cost math
- 200 gas per byte of bytecode at deployment
- A 100-byte unused function: 100 × 200 = 20,000 gas wasted at deployment
- A 500-byte unused module: 100,000 gas wasted

### Anti-patterns
```solidity
// Dead branch: constant false condition
bool public constant IS_V1 = false;
function process() external {
    if (IS_V1) {
        _legacyProcess();   // never executes — still compiled
    }
    _newProcess();
}

// Unused internal function
function _legacyProcess() internal {
    // ... 50 lines of bytecode that no live code path calls ...
}

// Deprecated function with no callers
function deprecatedFunction() external {
    revert("Deprecated");
}
```

### Optimized pattern
```solidity
// Removed: IS_V1, dead if branch, _legacyProcess, deprecatedFunction
function process() external {
    _newProcess();
}
```

### Detection
```bash
# Static analysis for unused functions and dead code
slither . --detect dead-code

# Measure bytecode size before and after
forge build --sizes
```

---

## DP-004: Vanity Addresses via CREATE2

### Pattern ID
`DP-004`

### Core concept
Every non-zero calldata byte costs 16 gas; zero bytes cost 4 gas. A 20-byte
Ethereum address with no leading zeros costs up to 320 gas when passed as
calldata. An address with N leading zero bytes saves N × 12 gas per call.

For ultra-high-frequency protocols (millions of calls/day), brute-forcing a
CREATE2 salt to find an address with leading zeros is a one-time offline
computation that yields perpetual per-call savings.

### Cost math
- Standard address (20 non-zero bytes): 20 × 16 = 320 gas in calldata
- Address with 4 leading zeros: (16 × 16) + (4 × 4) = 272 gas
- Saving: 48 gas per call (4 leading zeros)
- At 1,000,000 calls/day: 48,000,000 gas/day saved

### Computation cost
- 1 leading zero byte: ~256 iterations
- 2 leading zero bytes: ~65,536 iterations
- 4 leading zero bytes: ~4,294,967,296 iterations (use Rust-based tools)

### Pattern
```solidity
// Factory for deterministic deployment at vanity address
contract VanityDeployer {
    event Deployed(address indexed addr, bytes32 salt);

    function deploy(bytes memory bytecode, bytes32 salt) external returns (address addr) {
        assembly {
            addr := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        require(addr != address(0), "Deploy failed");
        emit Deployed(addr, salt);
    }

    function computeAddress(bytes32 salt, bytes32 bytecodeHash)
        external view returns (address)
    {
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff), address(this), salt, bytecodeHash
        )))));
    }
}
```

### Offline salt brute-forcing tools
- `cast create2` (Foundry): `cast create2 --starts-with 0000 --deployer <addr>`
- `create2crunch` (Rust): faster for many leading zeros
- Custom GPU scripts for 4+ leading zeros

### When NOT to apply
- Contracts deployed once and rarely called: the computation and engineering
  cost is not justified.
- When CREATE2 is not appropriate (mutable constructor arguments that vary
  per deployment change the bytecode hash).
- For most projects: apply only to the highest-frequency core protocol
  contracts (router, pool, vault entry points).
