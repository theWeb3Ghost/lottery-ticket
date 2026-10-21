# Raffle (Lottery Ticket)

A decentralized lottery smart contract built with [Chainlink VRF v2+](https://docs.chain.link/vrf) for provably fair winner selection. Built on [Foundry](https://book.getfoundry.sh/).

## Overview

The `Raffle` contract allows players to enter a lottery by paying an entrance fee. After a configurable time interval, the entire pot is awarded to a randomly selected winner via Chainlink's Verifiable Random Function (VRF). The contract supports Chainlink Automation (Keepers) for decentralized winner selection.

### Key Features

- **Provably fair randomness** — winners are selected using Chainlink VRF v2+
- **Automated execution** — `checkUpKeep` / `performUpKeep` pattern for Chainlink Automation
- **Secure payouts** — checks-effects-interactions pattern prevents re-entrancy
- **Configurable** — entry fee, interval, and VRF settings are set per-deployment
- **Gas optimized** — immutable variables, packed storage, minimal state updates

## Architecture

```
Raffle Contract
  ├── enterRaffle()          // Pay entry fee to join the lottery
  ├── checkUpKeep()          // Keeper-compatible: checks if winner should be drawn
  ├── performUpkeep()        // Triggers VRF request for randomness
  └── fulfillRandomWords()   // VRF callback: selects winner, transfers funds
```

### Lifecycle

```
1. OPEN  → Players enter by paying the entry fee
2. Interval elapses → checkUpKeep returns true
3. performUpkeep() → requests random words from VRF, state → CALCULATING
4. fulfillRandomWords() → winner selected, funds transferred, state → OPEN
5. Repeat from step 1
```

## Quick Start

### Install Foundry

```bash
curl -L https://foundry.paradigm.xyz/versions/1.0.0.4/install | bash
foundryup
```

### Build

```bash
forge build
```

### Test

```bash
forge test
```

### Format

```bash
forge fmt
```

## Contract

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

contract Raffle is VRFConsumerBaseV2Plus {
    enum RaffleState { OPEN, CALCULATING }

    uint256 public immutable i_entryFee;
    uint256 public immutable i_interval;
    bytes32 public immutable i_keyHash;
    uint256 public immutable i_subscriptionId;
    uint32 public immutable i_callbackGasLimit;

    address payable[] private s_players;
    address public s_recentWinner;
    RaffleState private s_raffleState;
    uint256 private s_lastTimestamp;
    // ...
}
```

## Deployment

```bash
forge script script/Raffle.s.sol:RaffleScript \
  --rpc-url <RPC_URL> \
  --private-key <PRIVATE_KEY> \
  --broadcast
```

Ensure you have:
1. A funded Chainlink VRF subscription on the target chain
2. The raffle contract added as a VRF consumer

## Configuration

| Parameter | Description |
|-----------|-------------|
| `entryFee` | Minimum ETH to enter the raffle |
| `interval` | Time between draws (seconds) |
| `vrfCoordinator` | Chainlink VRF coordinator address |
| `keyHash` | VRF key hash (gas lane) |
| `subscriptionId` | VRF subscription ID |
| `callbackGasLimit` | Gas limit for the fulfillRandomWords callback |
