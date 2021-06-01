// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.6/VRFConsumerBase.sol";

import "../interfaces/IPotController.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT WHICH USES HARDCODED VALUES FOR CLARITY.
 * PLEASE DO NOT USE THIS CODE IN PRODUCTION.
 */
contract RandomNumberGenerator is VRFConsumerBase, Ownable {

    /* ========== STATE VARIABLES ========== */

    bytes32 internal keyHash;
    uint256 internal fee;

    mapping(address => uint) private _pots;
    mapping(address => bool) private _availablePot;
    mapping(bytes32 => address) private _requestIds;

    /* ========== MODIFIER ========== */

    modifier onlyPot {
        require(_availablePot[msg.sender], "RandomNumberConsumer: is not pot contract.");
        _;
    }

    /* ========== EVENTS ========== */

    event RequestRandomness(
        bytes32 indexed requestId,
        bytes32 keyHash,
        uint256 seed
    );

    event RequestRandomnessFulfilled(
        bytes32 indexed requestId,
        uint256 randomness
    );


    /**
     * Constructor inherits VRFConsumerBase
     *
     * Network: BSC
     * Chainlink VRF Coordinator address: 0x747973a5A2a4Ae1D3a8fDF5479f1514F65Db9C31
     * LINK token address:                0x404460C6A5EdE2D891e8297795264fDe62ADBB75
     * Key Hash: 0xc251acd21ec4fb7f31bb8868288bfdbaeb4fbfec2df3735ddbd4f7dc8d60103c
     */
    constructor(address _vrfCoordinator, address _linkToken)
    VRFConsumerBase(
        _vrfCoordinator,
        _linkToken
    ) public
    {
        keyHash = 0xc251acd21ec4fb7f31bb8868288bfdbaeb4fbfec2df3735ddbd4f7dc8d60103c;
        fee = 0.2 * 10 ** 18; // 0.2 LINK (Varies by network)
    }

    /* ========== VIEW FUNCTIONS ========== */

    function availablePot(address pot) public view returns(bool) {
        return _availablePot[pot];
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setKeyHash(bytes32 _keyHash) external onlyOwner {
        keyHash = _keyHash;
    }

    function setFee(uint256 _fee) external onlyOwner {
        fee = _fee;
    }

    function setPotAddress(address potAddress, bool activate) external onlyOwner {
        _availablePot[potAddress] = activate;
    }

    /* ========== MUTATE FUNCTIONS ========== */

    function getRandomNumber(uint potId, uint256 userProvidedSeed) public onlyPot returns (bytes32 requestId) {
        require(LINK.balanceOf(address(this)) >= fee, "Not enough LINK - fill contract with faucet");
        _pots[msg.sender] = potId;
        requestId = requestRandomness(keyHash, fee, userProvidedSeed);
        _requestIds[requestId] = msg.sender;

        emit RequestRandomness(requestId, keyHash, userProvidedSeed);
    }

    /* ========== CALLBACK FUNCTIONS ========== */

    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        address potAddress = _requestIds[requestId];
        IPotController(potAddress).numbersDrawn(_pots[potAddress], requestId, randomness);

        emit RequestRandomnessFulfilled(requestId, randomness);

        delete _requestIds[requestId];
    }

    // function withdrawLink() external {} - Implement a withdraw function to avoid locking your LINK in the contract
}
