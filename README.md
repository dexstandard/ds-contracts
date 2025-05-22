# Dexstandard Contracts

## Contracts info

- **OrderManagerV1**  
  UUPS-upgradeable contract for EIP-712 stop-market orders.

- **DCAOrderManagerV1**  
  UUPS-upgradeable contract for scheduled DCA orders.

## Deployment Addresses

| Network             | OrderManagerV1                                                                            | DCAOrderManagerV1                                                                         |
| ------------------- | ----------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| **Arbitrum One**    | [0xc6fce2a…98794](https://arbiscan.io/address/0xc6fce2a8a5c44307961bc01ed7a191ced4a98794) | [0xe69ae8f…b009](https://arbiscan.io/address/0xe69ae8f231e4a394aef7bee6d307915c9090b009)  |
| **BNB Smart Chain** | [0xa61b5b1…64eb6](https://bscscan.com/address/0xa61b5b13923f05fa025534f6cc18d0c849164eb6) | [0x43f28bb…e4125](https://bscscan.com/address/0x43f28bb23cbf4afe6b9ffe337bf1cc8c861e4125) |

---

## OrderManagerV1

OrderManagerV1 lets you place automated stop-market, take-profit, and stop-loss orders across multiple DEXs with built-in fee handling and safe upgrades.

### Core Features

- **Stop-Market Orders**  
  Open a position when price crosses a threshold, on-chain execution of signed orders.
- **Take-Profit & Stop-Loss**  
  Separate flows to close above/below user-specified min outputs.
- **Multi-DEX Routing**  
  Swap through Uniswap, SushiSwap or PancakeSwap via a single `dexIndex`.
- **EIP-712 Signature Verification**  
  Ensures only the order’s signer can submit.
- **Executor Fees & Gas Refunds**  
  Optionally swap a portion to WETH and refund the executor in native ETH/BNB.
- **UUPS Upgradeability**  
  Two-day timelock for safe implementation swaps.

### Execution flow

1. **Order Creation (Off-Chain)**
   - User builds a `StopMarketOrder` struct and signs it (EIP-712).
2. **Open Position**
   - Executor calls `executeOrder(...)`.  
     • Verifies signature, marks position open, transfers `amountIn`, routes swap via chosen DEX, records `amountOut`.
3. **Close Position**
   - For profit: executor calls `executeTakeProfit(...)`.
   - For loss: executor calls `executeStopLoss(...)`.
   - Both verify the original order, ensure position was opened, transfer tokens back into the contract, swap out at or above the user’s min, refund fees.
4. **Fee Handling**
   - Optional fee swap to WETH, withdrawal to native token, then paid out to executor.

## DCAOrderManagerV1

DCAOrderManagerV1 breaks your investment into scheduled chunks for dollar-cost averaging, optionally earning yield in a vault, with executor rewards and cancellation support.

### Core Features

- **Scheduled Sub-Orders**  
  Split a single deposit into `totalOrders` pieces, executed every `interval` seconds.
- **Vault Integration**  
  Optional `VaultStrict` deposit for idle funds; auto-redeem shares per sub-order.
- **Multi-DEX Routing**  
  Supports Uniswap V3 and Pancake V3 via a `DexEnum` index.
- **Executor Fees & Gas Refunds**  
  Swap a fee slice to WETH, withdraw to native, and pay the executor.
- **Cancellation & Refund**  
  User or executor can cancel an active order and refund remaining tokens or vault shares.
- **UUPS Upgradeability**  
  Two-day timelock before new implementations can be applied.

### Execution Flow

1. **Order Creation**
   - User calls `createOrder(...)` with params.
   - Contract validates inputs, optionally deposits funds into `VaultStrict` or pulls tokens, and stores the `DCAOrder` struct.
2. **Sub-Order Execution**
   - Executor calls `executeOrder(...)`.  
     • Validate & calculates spend amount (redeems vault shares or uses token balance).  
     • Executes main swap & fee swap, pays executor.  
     • Increments `executedOrders`, updates `nextExecution`, marks closed if done.
3. **Cancellation**
   - User or executor calls `cancelOrder(orderId)` before final execution.
   - Marks order closed and refunds remaining tokens or vault shares to the user.

## Local Build & Testing

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Deploy

#### Arbitrum Order manager

```shell
forge script script/arb/OrderManagerV1Deploy.s.sol:OrderManagerV1Deploy --rpc-url https://arb1.arbitrum.io/rpc --private-key <your_private_key> --broadcast
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

#### Arbitrum DCA Order Manager

```shell
forge script script/arb/dca/DCAOrderManagerV1Deploy.s.sol:DCAOrderManagerV1Deploy --rpc-url https://arb1.arbitrum.io/rpc --private-key <your_private_key> --broadcast
```

```shell
forge verify-contract --chain arbitrum <contract_address> src/dca/DCAOrderManagerV1.sol:DCAOrderManagerV1 --etherscan-api-key <your_etherscan_api_key>
```

```shell
forge verify-contract --chain arbitrum <contract_address> \
lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy \
--etherscan-api-key <your_etherscan_api_key> \
--constructor-args <abi-encoded-arguments-0x123>
```

#### Arbitrum AAVEV3 with VaultStrict for DCA Order Manager

```shell
forge script script/arb/dca/StrategyAaveV3SupplyUSDTWithVaultStrict.s.sol:StrategyAaveV3SupplyUSDTWithVaultStrict --rpc-url https://arb1.arbitrum.io/rpc --private-key <your_private_key> --broadcast
```

```shell
forge verify-contract --chain arbitrum <contract_address> src/yield/vault/VaultStrict.sol:VaultStrict --etherscan-api-key <your_etherscan_api_key>
```

```shell
forge verify-contract --chain arbitrum <contract_address> src/yield/strategies/aave/StrategyAaveV3Supply.sol:StrategyAaveV3Supply --etherscan-api-key <your_etherscan_api_key>
```

```shell
forge verify-contract --chain arbitrum <contract_address> \
lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy \
--etherscan-api-key <your_etherscan_api_key> \
--constructor-args <abi-encoded-arguments-0x123>
```

#### BNB

```shell
forge script script/bnb/OrderManagerV1Deploy.s.sol:OrderManagerV1Deploy --rpc-url https://bsc-dataseed.bnbchain.org --private-key <your_private_key> --broadcast
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

#### BNB DCA Order Manager

```shell
forge script script/bnb/dca/DCAOrderManagerV1Deploy.s.sol:DCAOrderManagerV1Deploy --rpc-url https://bsc-dataseed.bnbchain.org --private-key <your_private_key> --broadcast
```

```shell
forge verify-contract --chain bsc <contract_address> src/dca/DCAOrderManagerV1.sol:DCAOrderManagerV1 --etherscan-api-key <your_etherscan_api_key>
```

```shell
forge verify-contract --chain bsc <contract_address> \
lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy \
--etherscan-api-key <your_etherscan_api_key> \
--constructor-args <abi-encoded-arguments-0x123>
```

#### BNB AAVEV3 with VaultStrict for DCA Order Manager

```shell
forge script script/bnb/dca/StrategyAaveV3SupplyUSDTWithVaultStrict.s.sol:StrategyAaveV3SupplyUSDTWithVaultStrict --rpc-url https://bsc-dataseed.bnbchain.org --private-key <your_private_key> --broadcast
```

```shell
forge verify-contract --chain bsc <contract_address> src/yield/vault/VaultStrict.sol:VaultStrict --etherscan-api-key <your_etherscan_api_key>
```

```shell
forge verify-contract --chain bsc <contract_address> src/yield/strategies/aave/StrategyAaveV3Supply.sol:StrategyAaveV3Supply --etherscan-api-key <your_etherscan_api_key>
```

```shell
forge verify-contract --chain bsc <contract_address> \
lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy \
--etherscan-api-key <your_etherscan_api_key> \
--constructor-args <abi-encoded-arguments-0x123>
```

### Upgrade

#### Arbitrum

```shell
forge script script/arb/OrderManagerV1ScheduleUpgrade.s.sol:OrderManagerV1ScheduleUpgrade --rpc-url https://arb1.arbitrum.io/rpc --private-key <your_private_key> --broadcast
```

```shell
forge script script/arb/OrderManagerV1Upgrade.s.sol:OrderManagerV1Upgrade --rpc-url https://arb1.arbitrum.io/rpc --private-key <your_private_key> --broadcast
```

#### BNB

```shell
forge script script/bnb/OrderManagerV1ScheduleUpgrade.s.sol:OrderManagerV1ScheduleUpgrade --rpc-url https://bsc-dataseed.bnbchain.org --private-key <your_private_key> --broadcast
```

```shell
forge script script/bnb/OrderManagerV1Upgrade.s.sol:OrderManagerV1Upgrade --rpc-url https://bsc-dataseed.bnbchain.org --private-key <your_private_key> --broadcast
```
