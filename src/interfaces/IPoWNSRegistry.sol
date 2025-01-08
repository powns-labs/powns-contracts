// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPoWNSRegistry
 * @notice Interface for the PoWNS Registry contract
 */
interface IPoWNSRegistry {
    // ============ Enums ============
    
    enum DomainState {
        Available,      // Not registered, can be claimed
        Active,         // Registered and owned
        Expired,        // Past expiration, in grace period countdown
        GracePeriod,    // 90-day grace period, only owner can renew
        Auction,        // Dutch difficulty auction
        Released        // Released by owner, deposit refunded
    }

    // ============ Structs ============
    
    struct Domain {
        address owner;
        uint256 expires;
        uint256 registeredAt;
        DomainState state;
    }

    // ============ Events ============
    
    event DomainRegistered(
        string indexed nameHash,
        string name,
        address indexed owner,
        address indexed miner,
        uint256 expires,
        uint256 difficulty
    );
    
    event DomainRenewed(
        string indexed nameHash,
        string name,
        address indexed owner,
        uint256 newExpires,
        uint8 additionalYears
    );
    
    event DomainReleased(
        string indexed nameHash,
        string name,
        address indexed owner,
        uint256 depositRefunded
    );
    
    event DomainTransferred(
        string indexed nameHash,
        address indexed from,
        address indexed to
    );

    // ============ Registration Functions ============
    
    /**
     * @notice Register a new domain with PoW
     * @param name The domain name to register
     * @param owner The address that will own the domain NFT
     * @param miner The address that computed the PoW (receives rewards)
     * @param nonce The nonce that satisfies the PoW requirement
     * @param years_ Number of years to register (1-10)
     */
    function register(
        string calldata name,
        address owner,
        address miner,
        uint256 nonce,
        uint8 years_
    ) external payable;

    /**
     * @notice Renew an existing domain with PoW
     * @param name The domain name to renew
     * @param nonce The nonce that satisfies the renewal PoW
     * @param additionalYears Number of years to add (1-10)
     */
    function renew(
        string calldata name,
        uint256 nonce,
        uint8 additionalYears
    ) external payable;

    /**
     * @notice Release a domain and get deposit refund
     * @param name The domain name to release
     */
    function release(string calldata name) external;

    // ============ Query Functions ============
    
    function ownerOf(string calldata name) external view returns (address);
    function expiresAt(string calldata name) external view returns (uint256);
    function getDomain(string calldata name) external view returns (Domain memory);
    function getState(string calldata name) external view returns (DomainState);
    function getDifficulty(string calldata name) external view returns (uint256);
    function isAvailable(string calldata name) external view returns (bool);
    
    // ============ PoW Verification ============
    
    function verifyPoW(
        string calldata name,
        address owner,
        address miner,
        uint256 nonce
    ) external view returns (bool);
    
    function computeTarget(string calldata name) external view returns (uint256);
}
