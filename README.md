# PoWNS Contracts

Smart contracts for PoW Name Service - a decentralized naming system where domain scarcity is determined by computational work, not capital.

## Contracts

| Contract                 | Description                                                     |
| ------------------------ | --------------------------------------------------------------- |
| `PoWNSRegistry`          | Core registry - domain registration, renewal, release (ERC-721) |
| `PoWNSVerifier`          | SHA256 PoW verification with miner address binding              |
| `DifficultyManager`      | Dark Gravity Wave difficulty adjustment algorithm               |
| `PoWNSResolver`          | Address, text, and contenthash resolution                       |
| `BountyVault`            | Outsourced mining bounty market                                 |
| `POWNSToken`             | Native $POWNS ERC-20 token with mining rewards                  |
| `POWNSStaking`           | Stake tokens for revenue sharing and voting power               |
| `ProtocolFeeDistributor` | 50% stakers / 30% DAO / 20% burn                                |
| `Marketplace`            | Domain trading - fixed price, auction, offers                   |
| `DomainLeasing`          | Rent out resolver control                                       |
| `TeamVesting`            | 1-year cliff + 3-year linear vesting                            |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         User / Miner                            │
└───────────────────────────────┬─────────────────────────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        ▼                       ▼                       ▼
┌───────────────┐     ┌─────────────────┐     ┌─────────────────┐
│ PoWNSRegistry │◄────│  PoWNSVerifier  │     │   BountyVault   │
│   (ERC-721)   │     │    (SHA256)     │     │(Mining Bounties)│
└───────┬───────┘     └─────────────────┘     └─────────────────┘
        │
        ├──────────────────────────────────────┐
        ▼                                      ▼
┌───────────────┐                    ┌─────────────────┐
│PoWNSResolver  │                    │   POWNSToken    │
│(Addr/Text/CID)│                    │    (ERC-20)     │
└───────────────┘                    └────────┬────────┘
                                              │
        ┌─────────────────────────────────────┼─────────────────┐
        ▼                                     ▼                 ▼
┌───────────────┐                    ┌───────────────┐ ┌───────────────┐
│  Marketplace  │                    │ POWNSStaking  │ │  TeamVesting  │
│(Trade Domains)│                    │(Revenue Share)│ │(Team Tokens)  │
└───────────────┘                    └───────┬───────┘ └───────────────┘
                                             │
                                             ▼
                                    ┌─────────────────┐
                                    │FeeDistributor   │
                                    │50%/30%/20%      │
                                    └─────────────────┘
```

## Build

```bash
# Install dependencies
forge install

# Build
forge build

# Test
forge test

# Test with verbosity
forge test -vvv
```

## Deploy

```bash
# Set environment
export PRIVATE_KEY=your_private_key
export RPC_URL=your_rpc_url

# Deploy all contracts
forge script script/Deploy.s.sol:DeployPoWNS --rpc-url $RPC_URL --broadcast
```

## Test Results

```
Running 20 tests
✅ test_ComputeHash
✅ test_DifficultyBits
✅ test_DifficultyBitsCharset
✅ test_DomainAuction
✅ test_DomainExpired
✅ test_DomainState
✅ test_InitialState
✅ test_InsufficientDeposit
✅ test_NameValidation
✅ test_RegisterDomain
✅ test_RegisterMultipleYears
✅ test_ReleaseDomain
✅ test_Target
✅ test_TransferDomain
✅ test_ValidNameChars
✅ test_VerifyPoW
✅ test_VerifyPoWFails
✅ test_CannotRegisterTwice
✅ test_CannotReleaseIfNotOwner
✅ test_CannotTransferIfNotOwner

20 passed, 0 failed
```

## Token Economics

| Allocation         | Percentage | Amount |
| ------------------ | ---------- | ------ |
| PoW Mining         | 40%        | 400M   |
| DAO Treasury       | 25%        | 250M   |
| Team (4yr vest)    | 15%        | 150M   |
| Early Contributors | 10%        | 100M   |
| Liquidity          | 10%        | 100M   |

## License

MIT
