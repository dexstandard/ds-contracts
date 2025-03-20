### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
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
