// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IResolver
 * @notice Interface for domain name resolution
 */
interface IResolver {
    // ============ Events ============
    
    event AddressChanged(bytes32 indexed nameHash, uint256 coinType, bytes newAddress);
    event TextChanged(bytes32 indexed nameHash, string key, string value);
    event ContenthashChanged(bytes32 indexed nameHash, bytes contenthash);

    // ============ Address Records ============
    
    /**
     * @notice Set address for a coin type
     * @param nameHash keccak256 of domain name
     * @param coinType SLIP-44 coin type (60 = ETH)
     * @param addr The address bytes
     */
    function setAddr(bytes32 nameHash, uint256 coinType, bytes calldata addr) external;
    
    /**
     * @notice Get address for a coin type
     */
    function addr(bytes32 nameHash, uint256 coinType) external view returns (bytes memory);
    
    /**
     * @notice Shorthand for ETH address (coinType 60)
     */
    function addr(bytes32 nameHash) external view returns (address);
    function setAddr(bytes32 nameHash, address addr) external;

    // ============ Text Records ============
    
    /**
     * @notice Set text record
     * @param nameHash keccak256 of domain name
     * @param key The record key (e.g., "avatar", "email", "url")
     * @param value The record value
     */
    function setText(bytes32 nameHash, string calldata key, string calldata value) external;
    
    /**
     * @notice Get text record
     */
    function text(bytes32 nameHash, string calldata key) external view returns (string memory);

    // ============ Contenthash ============
    
    /**
     * @notice Set contenthash (IPFS, Arweave, Swarm)
     */
    function setContenthash(bytes32 nameHash, bytes calldata hash) external;
    
    /**
     * @notice Get contenthash
     */
    function contenthash(bytes32 nameHash) external view returns (bytes memory);

    // ============ Batch Operations ============
    
    /**
     * @notice Set multiple records at once
     */
    function multicall(bytes[] calldata data) external returns (bytes[] memory results);
}
