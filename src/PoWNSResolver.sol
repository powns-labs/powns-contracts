// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IResolver} from "./interfaces/IResolver.sol";

/**
 * @title PoWNSResolver
 * @notice Resolver for domain name records (addresses, text, contenthash)
 */
contract PoWNSResolver is IResolver, Ownable {
    // ============ Storage ============
    
    /// @notice Registry contract address
    address public registry;
    
    /// @notice Address records: nameHash => coinType => address bytes
    mapping(bytes32 => mapping(uint256 => bytes)) private _addresses;
    
    /// @notice Text records: nameHash => key => value
    mapping(bytes32 => mapping(string => string)) private _texts;
    
    /// @notice Contenthash records: nameHash => hash
    mapping(bytes32 => bytes) private _contenthashes;

    // ============ Errors ============
    
    error Unauthorized();
    error InvalidCoinType();

    // ============ Constructor ============
    
    constructor(address _registry) Ownable(msg.sender) {
        registry = _registry;
    }

    // ============ Modifiers ============
    
    modifier onlyOwnerOf(bytes32 nameHash) {
        // Query registry to check ownership
        (bool success, bytes memory data) = registry.staticcall(
            abi.encodeWithSignature("ownerOfHash(bytes32)", nameHash)
        );
        if (!success || abi.decode(data, (address)) != msg.sender) {
            revert Unauthorized();
        }
        _;
    }

    // ============ Address Records ============
    
    /// @notice Set address for a coin type (SLIP-44)
    function setAddr(
        bytes32 nameHash, 
        uint256 coinType, 
        bytes calldata addr_
    ) external onlyOwnerOf(nameHash) {
        _addresses[nameHash][coinType] = addr_;
        emit AddressChanged(nameHash, coinType, addr_);
    }
    
    /// @notice Get address for a coin type
    function addr(bytes32 nameHash, uint256 coinType) external view returns (bytes memory) {
        return _addresses[nameHash][coinType];
    }
    
    /// @notice Set ETH address (shorthand for coinType 60)
    function setAddr(bytes32 nameHash, address addr_) external onlyOwnerOf(nameHash) {
        _addresses[nameHash][60] = abi.encodePacked(addr_);
        emit AddressChanged(nameHash, 60, abi.encodePacked(addr_));
    }
    
    /// @notice Get ETH address (shorthand)
    function addr(bytes32 nameHash) external view returns (address) {
        bytes memory data = _addresses[nameHash][60];
        if (data.length == 0) return address(0);
        return abi.decode(abi.encodePacked(bytes12(0), data), (address));
    }

    // ============ Text Records ============
    
    /// @notice Set text record
    function setText(
        bytes32 nameHash, 
        string calldata key, 
        string calldata value
    ) external onlyOwnerOf(nameHash) {
        _texts[nameHash][key] = value;
        emit TextChanged(nameHash, key, value);
    }
    
    /// @notice Get text record
    function text(bytes32 nameHash, string calldata key) external view returns (string memory) {
        return _texts[nameHash][key];
    }

    // ============ Contenthash ============
    
    /// @notice Set contenthash (IPFS, Arweave, Swarm)
    function setContenthash(bytes32 nameHash, bytes calldata hash) external onlyOwnerOf(nameHash) {
        _contenthashes[nameHash] = hash;
        emit ContenthashChanged(nameHash, hash);
    }
    
    /// @notice Get contenthash
    function contenthash(bytes32 nameHash) external view returns (bytes memory) {
        return _contenthashes[nameHash];
    }

    // ============ Batch Operations ============
    
    /// @notice Execute multiple calls in one transaction
    function multicall(bytes[] calldata data) external returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);
            require(success, "Multicall failed");
            results[i] = result;
        }
    }

    // ============ Admin ============
    
    function setRegistry(address _registry) external onlyOwner {
        registry = _registry;
    }
}
