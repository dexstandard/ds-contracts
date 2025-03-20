## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

#### Arbitrum

```shell
$ forge script script/OrderManagerV1.s.arb.sol:OrderManagerV1Script --rpc-url https://arb1.arbitrum.io/rpc --private-key <your_private_key> --broadcast
```

```shell
forge verify-contract --chain arbitrum <contract_address> src/OrderManagerV1.sol:OrderManagerV1 --etherscan-api-key <your_etherscan_api_key>
```

```shell
forge verify-contract --chain arbitrum <contract_address> \
lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy \
--etherscan-api-key <your_etherscan_api_key> \
--constructor-args <abi-encoded-arguments-0x123>
```

#### BNB

```shell
$ forge script script/OrderManagerV1.s.bnb.sol:OrderManagerV1Script --rpc-url https://bsc-dataseed.bnbchain.org --private-key <your_private_key> --broadcast
```

```shell
forge verify-contract --chain bsc <contract_address> src/OrderManagerV1.sol:OrderManagerV1 --etherscan-api-key <your_etherscan_api_key>
```

```shell
forge verify-contract --chain bsc <contract_address> \
lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy \
--etherscan-api-key <your_etherscan_api_key> \
--constructor-args <abi-encoded-arguments-0x123>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
