// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title Raffle
 * @author theWeb3Ghost
 * @notice Decentralized lottery using Chainlink VRF v2+ for provably fair winner selection.
 * @dev Players enter by paying an entrance fee during the OPEN window.
 *      After a configurable interval, automation triggers winner selection.
 *      The entire contract balance is sent to the winner in one atomic step.
 */
contract Raffle is VRFConsumerBaseV2Plus {
    /* ========== Errors ========== */
    error Raffle_NotEnoughEth(uint256 required, uint256 provided);
    error Raffle_TransferFailed(address recipient, uint256 amount);
    error Raffle_NotOpen();
    error Raffle_UpkeepNotNeeded(uint256 balance, uint256 numPlayers, uint256 state);

    /* ========== Enums ========== */
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    /* ========== Constants ========== */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    /* ========== Immutable Constructor Args ========== */
    uint256 public immutable i_entryFee;
    uint256 public immutable i_interval;
    bytes32 public immutable i_keyHash;
    uint256 public immutable i_subscriptionId;
    uint32 public immutable i_callbackGasLimit;

    /* ========== Mutable State ========== */
    uint256 private s_lastTimestamp;
    address payable[] private s_players;
    address public s_lastWinner;
    RaffleState private s_raffleState;

    /* ========== Events ========== */
    event RaffleEntered(address indexed player, uint256 amount);
    event WinnerSelected(address indexed winner, uint256 amount, uint256 requestId);

    /* ========== Constructor ========== */
    constructor(
        uint256 entryFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 keyHash,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entryFee = entryFee;
        i_interval = interval;
        s_lastTimestamp = block.timestamp;
        i_keyHash = keyHash;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
    }

    /* ========== Core Functions ========== */

    /**
     * @notice Enter the raffle by paying the entry fee.
     * @dev Only callable when the raffle is in OPEN state.
     */
    function enterRaffle() external payable {
        if (msg.value < i_entryFee) {
            revert Raffle_NotEnoughEth(i_entryFee, msg.value);
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle_NotOpen();
        }
        s_players.push(payable(msg.sender));
        emit RaffleEntered(msg.sender, msg.value);
    }

    /**
     * @notice Automation-check function: determines if a winner should be picked.
     * @dev Used by Keepers / off-chain automation to trigger performUpkeep.
     *      Returns true if:
     *        1. The raffle is OPEN
     *        2. The interval has elapsed since the last timestamp update
     *        3. At least one player has entered
     *        4. The contract holds a positive balance
     */
    function checkUpKeep(
        bytes memory /* checkData */
    )
        public
        view
        returns (
            bool upkeepNeeded,
            bytes memory /* performData */
        )
    {
        bool isOpen = (s_raffleState == RaffleState.OPEN);
        bool timePassed = ((block.timestamp - s_lastTimestamp) >= i_interval);
        bool hasPlayers = (s_players.length > 0);
        bool hasBalance = (address(this).balance > 0);
        upkeepNeeded = (isOpen && timePassed && hasPlayers && hasBalance);
        return (upkeepNeeded, "0x0");
    }

    /**
     * @notice Automation function: triggers VRF random winner selection.
     * @dev Only callable when checkUpKeep returns true.
     *      Sends a randomness request to Chainlink VRF, which will later
     *      call fulfillRandomWords with the random seed.
     */
    function performUpkeep(
        bytes memory /* performData */
    )
        external
    {
        (bool upkeepNeeded,) = checkUpKeep("");
        if (!upkeepNeeded) {
            revert Raffle_UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }

        // Transition to CALCULATING state — prevents new entries during VRF round
        s_raffleState = RaffleState.CALCULATING;
        s_lastTimestamp = block.timestamp; // Reset interval timer for the next round

        // Build the VRF random-words request
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
            keyHash: i_keyHash,
            subId: i_subscriptionId,
            requestConfirmations: REQUEST_CONFIRMATIONS,
            callbackGasLimit: i_callbackGasLimit,
            numWords: NUM_WORDS,
            extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
        });

        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);
    }

    /**
     * @notice VRF callback: selects a random winner and transfers the entire pot.
     * @dev Called by the VRFCoordinator after the randomness request is fulfilled.
     *      Uses nonReentrant pattern (via the CALCULATING state) and updates all
     *      state before the ETH transfer to prevent re-entrancy.
     */
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal virtual override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];

        // --- State updates BEFORE the transfer (checks-effects-interactions pattern) ---
        s_lastWinner = winner;
        s_lastTimestamp = block.timestamp; // Reset interval timer for the next round
        s_raffleState = RaffleState.OPEN; // Reopen for the next round
        s_players = new address payable[](0); // Clear the player list

        uint256 amountToSend = address(this).balance;

        // --- External call (interaction) ---
        (bool success,) = winner.call{value: amountToSend}("");
        if (!success) {
            revert Raffle_TransferFailed(winner, amountToSend);
        }

        emit WinnerSelected(winner, amountToSend, requestId);
    }

    /* ========== View / Getters ========== */

    function getEntryFee() external view returns (uint256) {
        return i_entryFee;
    }

    function getPlayers() external view returns (address payable[] memory) {
        return s_players;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getNumberOfPlayers() external view returns (uint256) {
        return s_players.length;
    }
}
