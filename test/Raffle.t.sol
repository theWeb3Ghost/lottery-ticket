// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {Raffle} from "../src/Raffle.sol";
import {
    VRFCoordinatorV2_5Mock
} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {
    VRFV2PlusClient
} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

contract RaffleTest is Test {
    VRFCoordinatorV2_5Mock internal vrfCoordinator;
    Raffle internal raffle;
    Raffle internal raffle2;

    uint256 internal constant ENTRY_FEE = 1 ether;
    uint256 internal constant INTERVAL = 1 days;
    bytes32 internal constant KEY_HASH = bytes32(uint256(1));
    uint256 internal s_subscriptionId;
    uint32 internal constant CALLBACK_GAS_LIMIT = 200_000;

    address internal constant PLAYER1 = address(100);
    address internal constant PLAYER2 = address(200);
    address internal constant PLAYER3 = address(300);

    function setUp() public {
        // Deploy mock VRF coordinator
        // weiPerUnitLink is set very high so LINK payment is negligible
        vrfCoordinator = new VRFCoordinatorV2_5Mock(
            0, // baseFee
            1, // gasPrice
            1e18 // weiPerUnitLink — high so LINK payment is tiny (1 LINK = 1e18 wei)
        );

        // Create a VRF subscription (returns the dynamically-generated subId)
        uint256 subId = vrfCoordinator.createSubscription();
        s_subscriptionId = subId;

        // Fund the subscription
        vrfCoordinator.fundSubscription(subId, 10 ether);

        // Deploy the raffle
        raffle = new Raffle(ENTRY_FEE, INTERVAL, address(vrfCoordinator), KEY_HASH, subId, CALLBACK_GAS_LIMIT);

        // Add the raffle as a consumer of the subscription
        vrfCoordinator.addConsumer(subId, address(raffle));

        // Deploy a second raffle (for testing multiple instances / different configs)
        raffle2 = new Raffle(ENTRY_FEE, INTERVAL, address(vrfCoordinator), KEY_HASH, subId, CALLBACK_GAS_LIMIT);
        vrfCoordinator.addConsumer(subId, address(raffle2));
    }

    /* ========== Constructor & Initialization Tests ========== */

    function test_Constructor_SetsImmutableVariables() public {
        assertEq(raffle.getEntryFee(), ENTRY_FEE);
        assertEq(uint256(raffle.getRaffleState()), uint256(Raffle.RaffleState.OPEN));
        assertEq(raffle.getNumberOfPlayers(), 0);
    }

    /* ========== enterRaffle Tests ========== */

    function test_EnterRaffle_WithExactFee_Succeeds() public {
        vm.deal(PLAYER1, ENTRY_FEE);
        vm.prank(PLAYER1);
        raffle.enterRaffle{value: ENTRY_FEE}();

        assertEq(raffle.getNumberOfPlayers(), 1);
        address payable[] memory players = raffle.getPlayers();
        assertEq(players[0], PLAYER1);
    }

    function test_EnterRaffle_WithMoreThanFee_Succeeds() public {
        vm.deal(PLAYER1, ENTRY_FEE + 1 ether);
        vm.prank(PLAYER1);
        raffle.enterRaffle{value: ENTRY_FEE + 1 ether}();

        assertEq(raffle.getNumberOfPlayers(), 1);
    }

    function test_EnterRaffle_WithLessThanFee_Reverts() public {
        vm.deal(PLAYER1, ENTRY_FEE - 1);
        vm.prank(PLAYER1);
        vm.expectRevert(abi.encodeWithSignature("Raffle_NotEnoughEth(uint256,uint256)", ENTRY_FEE, ENTRY_FEE - 1));
        raffle.enterRaffle{value: ENTRY_FEE - 1}();
    }

    function test_EnterRaffle_WhenNotOpen_Reverts() public {
        vm.deal(PLAYER1, ENTRY_FEE);
        vm.prank(PLAYER1);
        raffle.enterRaffle{value: ENTRY_FEE}();

        // Manually set state to CALCULATING by calling performUpkeep
        vm.warp(block.timestamp + INTERVAL);
        raffle.performUpkeep("");

        // Now state is CALCULATING, entering should revert
        vm.prank(PLAYER2);
        vm.deal(PLAYER2, ENTRY_FEE);
        vm.expectRevert(abi.encodeWithSignature("Raffle_NotOpen()"));
        raffle.enterRaffle{value: ENTRY_FEE}();
    }

    function test_EnterRaffle_EmitsEvent() public {
        vm.deal(PLAYER1, ENTRY_FEE);
        vm.prank(PLAYER1);
        vm.expectEmit(true, true, true, true);
        emit Raffle.RaffleEntered(PLAYER1, ENTRY_FEE);
        raffle.enterRaffle{value: ENTRY_FEE}();
    }

    /* ========== checkUpKeep Tests ========== */

    function test_CheckUpKeep_NotNeeded_WhenNoPlayers() public {
        vm.warp(block.timestamp + INTERVAL);
        (bool upkeepNeeded,) = raffle.checkUpKeep("");
        assertFalse(upkeepNeeded);
    }

    function test_CheckUpKeep_NotNeeded_WhenIntervalNotPassed() public {
        // Enter a player but don't advance time
        vm.deal(PLAYER1, ENTRY_FEE);
        vm.prank(PLAYER1);
        raffle.enterRaffle{value: ENTRY_FEE}();

        (bool upkeepNeeded,) = raffle.checkUpKeep("");
        assertFalse(upkeepNeeded);
    }

    function test_CheckUpKeep_NotNeeded_WhenClosed() public {
        // This test verifies that after performUpkeep, state changes prevent re-entry
        vm.deal(PLAYER1, ENTRY_FEE);
        vm.prank(PLAYER1);
        raffle.enterRaffle{value: ENTRY_FEE}();

        vm.warp(block.timestamp + INTERVAL);
        raffle.performUpkeep("");

        // After performUpkeep, state is CALCULATING
        (bool upkeepNeeded,) = raffle.checkUpKeep("");
        assertFalse(upkeepNeeded);
    }

    function test_CheckUpKeep_Needed_WhenAllConditionsMet() public {
        vm.deal(PLAYER1, ENTRY_FEE);
        vm.prank(PLAYER1);
        raffle.enterRaffle{value: ENTRY_FEE}();

        vm.warp(block.timestamp + INTERVAL);
        (bool upkeepNeeded,) = raffle.checkUpKeep("");
        assertTrue(upkeepNeeded);
    }

    /* ========== performUpkeep Tests ========== */

    function test_PerformUpKeep_TransitionsToCalculating() public {
        vm.deal(PLAYER1, ENTRY_FEE);
        vm.prank(PLAYER1);
        raffle.enterRaffle{value: ENTRY_FEE}();

        vm.warp(block.timestamp + INTERVAL);
        raffle.performUpkeep("");

        assertEq(uint256(raffle.getRaffleState()), uint256(Raffle.RaffleState.CALCULATING));
    }

    function test_PerformUpKeep_Reverts_WhenNoUpkeepNeeded() public {
        vm.expectRevert(
            abi.encodeWithSignature(
                "Raffle_UpkeepNotNeeded(uint256,uint256,uint256)", 0, 0, uint256(Raffle.RaffleState.OPEN)
            )
        );
        raffle.performUpkeep("");
    }

    /* ========== Full Raffle Flow Tests ========== */

    function test_FullRaffleFlow_SelectsWinnerAndResets() public {
        // Enter the raffle
        vm.deal(PLAYER1, ENTRY_FEE);
        vm.deal(PLAYER2, ENTRY_FEE);
        vm.deal(PLAYER3, ENTRY_FEE);

        vm.prank(PLAYER1);
        raffle.enterRaffle{value: ENTRY_FEE}();
        vm.prank(PLAYER2);
        raffle.enterRaffle{value: ENTRY_FEE}();
        vm.prank(PLAYER3);
        raffle.enterRaffle{value: ENTRY_FEE}();

        // Advance time past the interval
        vm.warp(block.timestamp + INTERVAL);

        // Trigger upkeep
        raffle.performUpkeep("");

        // Verify state is CALCULATING
        assertEq(uint256(raffle.getRaffleState()), uint256(Raffle.RaffleState.CALCULATING));

        // Fulfill the VRF request (this calls fulfillRandomWords internally)
        vrfCoordinator.fulfillRandomWords(1, address(raffle));

        // After fulfillment, the state should be OPEN again
        assertEq(uint256(raffle.getRaffleState()), uint256(Raffle.RaffleState.OPEN));

        // Players should be cleared
        assertEq(raffle.getNumberOfPlayers(), 0);

        // A winner should have been selected
        assert(raffle.s_lastWinner() != address(0));
    }

    function test_FullRaffleFlow_WinnerReceivesAllFunds() public {
        vm.deal(PLAYER1, ENTRY_FEE);
        vm.prank(PLAYER1);
        raffle.enterRaffle{value: ENTRY_FEE}();

        uint256 balanceBefore = address(raffle).balance;
        assertEq(balanceBefore, ENTRY_FEE);

        vm.warp(block.timestamp + INTERVAL);
        raffle.performUpkeep("");
        vrfCoordinator.fulfillRandomWords(1, address(raffle));

        // Contract balance should be zero after the winner is paid
        assertEq(address(raffle).balance, 0);
        // A winner should have been selected
        assert(raffle.s_lastWinner() != address(0));
    }

    function test_FullRaffleFlow_CanEnterNextRoundAfterWinnerSelected() public {
        vm.deal(PLAYER1, ENTRY_FEE);
        vm.prank(PLAYER1);
        raffle.enterRaffle{value: ENTRY_FEE}();

        vm.warp(block.timestamp + INTERVAL);
        raffle.performUpkeep("");
        vrfCoordinator.fulfillRandomWords(1, address(raffle));

        // Now we should be able to enter again
        vm.prank(PLAYER2);
        vm.deal(PLAYER2, ENTRY_FEE);
        raffle.enterRaffle{value: ENTRY_FEE}();

        assertEq(raffle.getNumberOfPlayers(), 1);
    }

    function test_SubscriptionFunding_IsSet() public {
        (uint96 balance,,,,) = vrfCoordinator.getSubscription(s_subscriptionId);
        assertGt(balance, 0);
    }

    /* ========== Fuzz Tests ========== */

    function testFuzz_EnterRaffle_MultiplePlayers(uint256 numPlayers) public {
        numPlayers = bound(numPlayers, 1, 100);

        for (uint256 i = 0; i < numPlayers; i++) {
            address player = address(uint160(uint256(uint160(PLAYER1)) + i));
            vm.deal(player, ENTRY_FEE);
            vm.prank(player);
            raffle.enterRaffle{value: ENTRY_FEE}();
        }

        assertEq(raffle.getNumberOfPlayers(), numPlayers);
    }

    /* ========== Multiple Raffles ========== */

    function test_MultipleRaffles_Independent() public {
        vm.deal(PLAYER1, ENTRY_FEE);
        vm.prank(PLAYER1);
        raffle.enterRaffle{value: ENTRY_FEE}();

        vm.deal(PLAYER2, ENTRY_FEE);
        vm.prank(PLAYER2);
        raffle2.enterRaffle{value: ENTRY_FEE}();

        assertEq(raffle.getNumberOfPlayers(), 1);
        assertEq(raffle2.getNumberOfPlayers(), 1);
    }
}
