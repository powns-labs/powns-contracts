// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IBountyVault
 * @notice Interface for the Bounty market
 */
interface IBountyVault {
    // ============ Structs ============
    
    struct Bounty {
        bytes32 nameHash;       // keccak256(name)
        address owner;          // NFT recipient
        address token;          // Payment token (address(0) = ETH)
        uint256 amount;         // Bounty amount
        uint256 deadline;       // Expiration timestamp
        uint8 minYears;         // Minimum registration years
        uint256 maxDifficulty;  // Maximum acceptable difficulty
        bool claimed;           // Whether bounty has been claimed
        bool cancelled;         // Whether bounty was cancelled
    }

    // ============ Events ============
    
    event BountyCreated(
        bytes32 indexed bountyId,
        bytes32 indexed nameHash,
        address indexed owner,
        address token,
        uint256 amount,
        uint256 deadline
    );
    
    event BountyClaimed(
        bytes32 indexed bountyId,
        address indexed miner,
        string name,
        uint256 amount
    );
    
    event BountyCancelled(
        bytes32 indexed bountyId,
        address indexed owner,
        uint256 refundAmount
    );

    // ============ Functions ============
    
    /**
     * @notice Create a bounty for mining a domain
     * @param nameHash keccak256 of the desired domain name
     * @param token Payment token (address(0) for ETH)
     * @param amount Bounty amount
     * @param deadline Expiration timestamp
     * @param minYears Minimum registration years
     * @param maxDifficulty Maximum acceptable difficulty (protection)
     */
    function createBounty(
        bytes32 nameHash,
        address token,
        uint256 amount,
        uint256 deadline,
        uint8 minYears,
        uint256 maxDifficulty
    ) external payable returns (bytes32 bountyId);

    /**
     * @notice Claim a bounty by submitting valid PoW
     * @param bountyId The bounty to claim
     * @param name The actual domain name
     * @param nonce The valid PoW nonce
     */
    function claimBounty(
        bytes32 bountyId,
        string calldata name,
        uint256 nonce
    ) external;

    /**
     * @notice Cancel a bounty and get refund
     * @param bountyId The bounty to cancel
     */
    function cancelBounty(bytes32 bountyId) external;

    /**
     * @notice Withdraw expired bounty funds
     * @param bountyId The expired bounty
     */
    function withdrawExpired(bytes32 bountyId) external;

    // ============ View Functions ============
    
    function getBounty(bytes32 bountyId) external view returns (Bounty memory);
    function getBountiesByOwner(address owner) external view returns (bytes32[] memory);
    function getActiveBounties() external view returns (bytes32[] memory);
}
