# Forward Hook
real-time liquidity underwriting for uniswap v4, with permissionless LP controls

A dynamic fee hook. An underwriter prices an agent by committing the hash of the offchain program
that determined them, so no fee can be set onchain without the logic that justifies it.

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

## Run the demo

Start a local chain, deploy the hook, then price a program on it. Use any of the keys `anvil` prints.

```shell
anvil
```

```shell
TARGET=anvil forge script script/DeployForwardHook.s.sol \
  --rpc-url http://127.0.0.1:8545 --broadcast --private-key $KEY
```

```shell
HOOK=<deployed hook> forge script script/LiquidityUnderwriter.s.sol \
  --rpc-url http://127.0.0.1:8545 --broadcast --private-key $KEY
```

`TARGET` is `anvil` for an empty chain, or `fork` / `testnet` where v4 already exists. The deploying
key holds both the admin and underwriter roles unless `.env` splits them.

Anyone holding the program's logic can then read back what it was priced at, and gets a revert if
their copy does not bind to a committed capability:

```shell
cast call $HOOK 'programFee(bytes32,bytes32)(uint24)' $STRUCTURE_HASH $LOGIC_HASH
```
