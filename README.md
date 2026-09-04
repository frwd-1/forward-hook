# Forward Hook

Real-time liquidity underwriting for Uniswap v4.

LPs leak value when informed flow trades against a pool that has not caught up to the rest of the market. Forward Hook is a Uniswap v4 dynamic-fee hook that prices that risk before the swap settles, without closing the pool or permissioning execution.

An offchain underwriter scores counterparties, then commits onchain the program that produced the score. The pool charges those agents a different LP fee. Unassigned flow keeps the default fee. No fee can be set without the logic that justifies it.

## Capabilities and fees

The underwriter (`UNDERWRITER_ROLE`) prices risk in two steps:

1. **Commit a program.** `commitProgram(structureHash, logicHash, fee)` binds the two hashes of the offchain program into a capability name and sets its fee. Recommitting the same program reprices it and leaves assigned agents in place.
2. **Assign agents.** `assignCapability(name, agent)` places an address under that capability.

On every swap the hook looks up the caller:

- Assigned to a committed capability → that capability's fee.
- Anyone else → the pool's default fee.

Fees are Uniswap v4 LP fees (hundredths of a bip). The demo prices ordinary flow at `3000` (0.30%) and a determined arbitrage trader at `10000` (1.00%). A higher fee on informed flow is what the LPs retain.

LPs with `LP_ROLE` can later reprice a committed capability without changing who sits under it. The underwriter can also change the default fee charged to unclassified flow.

Anyone holding the program can read what it is priced at. A copy that does not bind to a committed capability reverts:

```shell
cast call $HOOK 'programFee(bytes32,bytes32)(uint24)' $STRUCTURE_HASH $LOGIC_HASH
```

## Setup

Requires [Foundry](https://book.getfoundry.sh/getting-started/installation). Contract dependencies
are not committed, so install them into `lib/` after cloning:

```shell
forge install --no-git foundry-rs/forge-std@v1.16.2
forge install --no-git OpenZeppelin/uniswap-hooks@v1.2.1
forge build
```

## Test

```shell
forge test
```

The unit tests run offline. The two fork suites replay real mainnet arbitrage transactions and skip
themselves unless `MAINNET_RPC_URL` points at an archive node. Copy `.env.example` to `.env` to set it.

## Deploy

`TARGET` selects how the PoolManager is found. The deploying key holds both the admin and
underwriter roles unless `.env` splits them (`HOOK_ADMIN`, `UNDERWRITER`). Use any of the keys
`anvil` prints for local runs.

```shell
# empty local chain: deploys a PoolManager, then the hook
anvil
TARGET=anvil forge script script/DeployForwardHook.s.sol \
  --rpc-url http://127.0.0.1:8545 --broadcast --private-key $KEY

# mainnet fork: canonical PoolManager is already in state
anvil --fork-url $MAINNET_RPC_URL
TARGET=fork forge script script/DeployForwardHook.s.sol \
  --rpc-url http://127.0.0.1:8545 --broadcast --private-key $KEY

# testnet with a live v4 PoolManager (Sepolia, Unichain Sepolia, Base Sepolia)
TARGET=testnet forge script script/DeployForwardHook.s.sol \
  --rpc-url $TESTNET_RPC_URL --broadcast --private-key $KEY
```

Price a program on the deployed hook:

```shell
HOOK=<deployed hook> forge script script/LiquidityUnderwriter.s.sol \
  --rpc-url http://127.0.0.1:8545 --broadcast --private-key $KEY
```
