// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";

/**
 * @title RaffleScript
 * @notice Deployment script for the Raffle contract.
 *         Run with: forge script script/Raffle.s.sol:RaffleScript --rpc-url <RPC> --private-key <PK> --broadcast
 *
 * @dev Make sure the VRF subscription is created and funded BEFORE
 *      running this script. The raffle contract must be added as a
 *      consumer of that subscription after deployment.
 */
contract RaffleScript is Script {
    /**
     * @dev Configuration — replace with your own values before deploying.
     */
    uint256 internal constant ENTRY_FEE = 1 ether;
    uint256 internal constant INTERVAL = 1 days; // 1 day between winner selections
    bytes32 internal constant KEY_HASH = bytes32(uint256(1)); // VRF key hash (testnet: use real key hash)
    uint256 internal constant SUBSCRIPTION_ID = 1; // Chainlink VRF subscription ID
    uint32 internal constant CALLBACK_GAS_LIMIT = 200_000;

    function run() external {
        // Example: Sepolia VRF Coordinator address
        // address vrfCoordinator = 0x8103B0A8A00be2DDC778e6e7eFD027d4b50b00b5;
        address vrfCoordinator = vm.envAddress("VRFCOORDINATOR");
        bytes32 keyHash = vm.envBytes32("KEY_HASH");
        uint256 subscriptionId = vm.envUint("SUBSCRIPTION_ID");

        vm.startBroadcast();

        Raffle raffle = new Raffle(ENTRY_FEE, INTERVAL, vrfCoordinator, keyHash, subscriptionId, CALLBACK_GAS_LIMIT);

        console.log("Raffle deployed at:", address(raffle));

        vm.stopBroadcast();
    }
}
