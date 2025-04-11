// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations eg structs, enums, etc
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// Constructor
// receive (if exists)
// fallback (if exists)
// external
// public
// internal
// private
// view/pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title Raffle Contract
 * @author Kofi Oghenevwegba
 * @notice This contract is for creating a simple raffle
 * @dev This implements Chainlink VRF to select a random winner
 */
contract Raffle is VRFConsumerBaseV2Plus {
    // Errors
    error Raffle__NotEnoughEth();
    error Raffle__UpkeepNotNeeded(uint256 balance, uint256 playersLength, uint256 raffleState);
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    // Type declarations
    enum RaffleState {
        OPEN, // 0
        CALCULATING // 1
    }

    // State variables
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    uint256 private immutable i_entranceFee;
    //@dev The interval at which the raffle can be picked in seconds
    uint256 private immutable i_interval;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    // Events
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);
    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() external payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEth();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }

        s_players.push(payable(msg.sender));
        emit RaffleEntered(msg.sender);
    }


// When should winners be picked?
/**
 * @dev This is the function that the chainlink nodes will call to see if the lottery is ready to have a winner picked.
 * The following should be true for this to return true:
 * 1. The time interval should have passed
 * 2. The state of the raffle should be OPEN
 * 3. The contract should have some ETH
 * 4. The contract should have some players
 * @param - ignored
 * @return upkeepNeeded  - true if it's time to restart the raffle
 * @return - ignored
 */
    function checkUpkeep(bytes memory /*checkData*/) public view returns(bool upkeepNeeded, bytes memory /*performData*/) {
        bool timeHasPassed =  ((block.timestamp - s_lastTimeStamp) >= i_interval);
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "");
    }

// Be automatically called
    function performUpkeep(bytes calldata /*performData*/) external {
        // check to see if enough time has passed
        (bool upkeepNeeded,) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }
        // if ((block.timestamp - s_lastTimeStamp) < i_interval) {
        //     revert Raffle__NotEnoughTime();
        // }

        s_raffleState = RaffleState.CALCULATING;

        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
            keyHash: i_keyHash, // Gas lane key hash value...Max gas price you want to pay for a request in wei
            subId: i_subscriptionId, // The subscription ID that this contract uses for funding requests
            requestConfirmations: REQUEST_CONFIRMATIONS, // How many confirmations the Chainlink node should wait before responding
            callbackGasLimit: i_callbackGasLimit, // The limit for how much gas to use for the callback request to your contract's fulfillRandomWords() function
            numWords: NUM_WORDS, //  How many random values to request.
            extraArgs: VRFV2PlusClient._argsToBytes(
                // set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
            )
        });

        s_vrfCoordinator.requestRandomWords(request);
    }

    function fulfillRandomWords(uint256 /*requestId*/, uint256[] calldata randomWords) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0); // Reset the players array
        s_lastTimeStamp = block.timestamp;
        emit WinnerPicked(s_recentWinner);

        (bool success,) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
        
    }

    /**
     * Getter functions
     */
    function getEntranceFee() public view returns (uint256) {
        return i_entranceFee;
    }

    function getPlayers() public view returns (address payable[] memory) {
        return s_players;
    }
}
