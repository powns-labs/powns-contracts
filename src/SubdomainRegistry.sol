// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SubdomainRegistry
 * @notice Manages subdomains for PoWNS domains
 * @dev Domain owners have full control over subdomain creation rules
 */
contract SubdomainRegistry is Ownable, ReentrancyGuard {
    // ============ Enums ============

    enum DistributionMode {
        Free, // Owner distributes freely
        Paid, // Pay to register
        PoW // Require PoW (like parent)
    }

    // ============ Structs ============

    struct SubdomainConfig {
        address owner; // Parent domain owner
        DistributionMode mode;
        uint256 price; // For Paid mode
        bool enabled; // Whether subdomains are enabled
        uint256 totalSubdomains;
    }

    struct Subdomain {
        address owner;
        uint256 parentTokenId;
        string label; // e.g., "blog" for "blog.alice.pow"
        uint256 createdAt;
        bool active;
    }

    // ============ Storage ============

    /// @notice Main registry contract
    address public registry;

    /// @notice Subdomain config by parent tokenId
    mapping(uint256 => SubdomainConfig) public configs;

    /// @notice Subdomains: parentTokenId => label hash => Subdomain
    mapping(uint256 => mapping(bytes32 => Subdomain)) public subdomains;

    /// @notice Subdomain owner lookup: full name hash => owner
    mapping(bytes32 => address) public subdomainOwners;

    /// @notice Resolver records for subdomains
    mapping(bytes32 => mapping(uint256 => bytes)) private _addresses;
    mapping(bytes32 => mapping(string => string)) private _texts;

    // ============ Events ============

    event SubdomainConfigured(
        uint256 indexed parentTokenId,
        DistributionMode mode,
        uint256 price,
        bool enabled
    );
    event SubdomainCreated(
        uint256 indexed parentTokenId,
        bytes32 indexed labelHash,
        string label,
        address indexed owner
    );
    event SubdomainTransferred(
        bytes32 indexed fullNameHash,
        address indexed from,
        address indexed to
    );
    event SubdomainRevoked(
        uint256 indexed parentTokenId,
        bytes32 indexed labelHash
    );

    // ============ Errors ============

    error NotParentOwner();
    error SubdomainsNotEnabled();
    error SubdomainExists();
    error SubdomainNotFound();
    error InsufficientPayment();
    error InvalidLabel();
    error NotSubdomainOwner();
    error TransferFailed();

    // ============ Constructor ============

    constructor(address _registry) Ownable(msg.sender) {
        registry = _registry;
    }

    // ============ Configuration ============

    /**
     * @notice Configure subdomain settings for a domain
     */
    function configure(
        uint256 parentTokenId,
        DistributionMode mode,
        uint256 price,
        bool enabled
    ) external {
        if (!_isParentOwner(parentTokenId, msg.sender)) revert NotParentOwner();

        configs[parentTokenId] = SubdomainConfig({
            owner: msg.sender,
            mode: mode,
            price: price,
            enabled: enabled,
            totalSubdomains: configs[parentTokenId].totalSubdomains
        });

        emit SubdomainConfigured(parentTokenId, mode, price, enabled);
    }

    // ============ Subdomain Creation ============

    /**
     * @notice Create a subdomain (owner only for Free mode)
     */
    function createSubdomainFree(
        uint256 parentTokenId,
        string calldata label,
        address to
    ) external {
        SubdomainConfig storage config = configs[parentTokenId];

        if (!config.enabled) revert SubdomainsNotEnabled();
        if (config.mode != DistributionMode.Free) revert SubdomainsNotEnabled();
        if (!_isParentOwner(parentTokenId, msg.sender)) revert NotParentOwner();

        _createSubdomain(parentTokenId, label, to);
    }

    /**
     * @notice Register a paid subdomain
     */
    function registerSubdomainPaid(
        uint256 parentTokenId,
        string calldata label
    ) external payable nonReentrant {
        SubdomainConfig storage config = configs[parentTokenId];

        if (!config.enabled) revert SubdomainsNotEnabled();
        if (config.mode != DistributionMode.Paid) revert SubdomainsNotEnabled();
        if (msg.value < config.price) revert InsufficientPayment();

        _createSubdomain(parentTokenId, label, msg.sender);

        // Send payment to parent owner
        (bool success, ) = config.owner.call{value: msg.value}("");
        if (!success) revert TransferFailed();
    }

    function _createSubdomain(
        uint256 parentTokenId,
        string calldata label,
        address to
    ) internal {
        if (!_isValidLabel(label)) revert InvalidLabel();

        bytes32 labelHash = keccak256(bytes(label));

        if (subdomains[parentTokenId][labelHash].active)
            revert SubdomainExists();

        subdomains[parentTokenId][labelHash] = Subdomain({
            owner: to,
            parentTokenId: parentTokenId,
            label: label,
            createdAt: block.timestamp,
            active: true
        });

        // Store full name hash for quick lookup
        bytes32 fullNameHash = keccak256(
            abi.encodePacked(label, ".", parentTokenId)
        );
        subdomainOwners[fullNameHash] = to;

        configs[parentTokenId].totalSubdomains++;

        emit SubdomainCreated(parentTokenId, labelHash, label, to);
    }

    // ============ Subdomain Management ============

    /**
     * @notice Transfer subdomain ownership
     */
    function transferSubdomain(
        uint256 parentTokenId,
        string calldata label,
        address to
    ) external {
        bytes32 labelHash = keccak256(bytes(label));
        Subdomain storage subdomain = subdomains[parentTokenId][labelHash];

        if (!subdomain.active) revert SubdomainNotFound();
        if (subdomain.owner != msg.sender) revert NotSubdomainOwner();

        address from = subdomain.owner;
        subdomain.owner = to;

        bytes32 fullNameHash = keccak256(
            abi.encodePacked(label, ".", parentTokenId)
        );
        subdomainOwners[fullNameHash] = to;

        emit SubdomainTransferred(fullNameHash, from, to);
    }

    /**
     * @notice Revoke a subdomain (parent owner only)
     */
    function revokeSubdomain(
        uint256 parentTokenId,
        string calldata label
    ) external {
        if (!_isParentOwner(parentTokenId, msg.sender)) revert NotParentOwner();

        bytes32 labelHash = keccak256(bytes(label));
        Subdomain storage subdomain = subdomains[parentTokenId][labelHash];

        if (!subdomain.active) revert SubdomainNotFound();

        subdomain.active = false;

        bytes32 fullNameHash = keccak256(
            abi.encodePacked(label, ".", parentTokenId)
        );
        delete subdomainOwners[fullNameHash];

        configs[parentTokenId].totalSubdomains--;

        emit SubdomainRevoked(parentTokenId, labelHash);
    }

    // ============ Resolver Functions ============

    /**
     * @notice Set address for subdomain
     */
    function setAddr(
        uint256 parentTokenId,
        string calldata label,
        uint256 coinType,
        bytes calldata addrData
    ) external {
        bytes32 labelHash = keccak256(bytes(label));
        Subdomain storage subdomain = subdomains[parentTokenId][labelHash];

        if (!subdomain.active) revert SubdomainNotFound();
        if (subdomain.owner != msg.sender) revert NotSubdomainOwner();

        bytes32 fullNameHash = keccak256(
            abi.encodePacked(label, ".", parentTokenId)
        );
        _addresses[fullNameHash][coinType] = addrData;
    }

    function addr(
        uint256 parentTokenId,
        string calldata label,
        uint256 coinType
    ) external view returns (bytes memory) {
        bytes32 fullNameHash = keccak256(
            abi.encodePacked(label, ".", parentTokenId)
        );
        return _addresses[fullNameHash][coinType];
    }

    /**
     * @notice Set text record for subdomain
     */
    function setText(
        uint256 parentTokenId,
        string calldata label,
        string calldata key,
        string calldata value
    ) external {
        bytes32 labelHash = keccak256(bytes(label));
        Subdomain storage subdomain = subdomains[parentTokenId][labelHash];

        if (!subdomain.active) revert SubdomainNotFound();
        if (subdomain.owner != msg.sender) revert NotSubdomainOwner();

        bytes32 fullNameHash = keccak256(
            abi.encodePacked(label, ".", parentTokenId)
        );
        _texts[fullNameHash][key] = value;
    }

    function text(
        uint256 parentTokenId,
        string calldata label,
        string calldata key
    ) external view returns (string memory) {
        bytes32 fullNameHash = keccak256(
            abi.encodePacked(label, ".", parentTokenId)
        );
        return _texts[fullNameHash][key];
    }

    // ============ View Functions ============

    function getSubdomain(
        uint256 parentTokenId,
        string calldata label
    ) external view returns (Subdomain memory) {
        bytes32 labelHash = keccak256(bytes(label));
        return subdomains[parentTokenId][labelHash];
    }

    function getConfig(
        uint256 parentTokenId
    ) external view returns (SubdomainConfig memory) {
        return configs[parentTokenId];
    }

    function ownerOf(
        uint256 parentTokenId,
        string calldata label
    ) external view returns (address) {
        bytes32 labelHash = keccak256(bytes(label));
        return subdomains[parentTokenId][labelHash].owner;
    }

    // ============ Internal ============

    function _isParentOwner(
        uint256 tokenId,
        address user
    ) internal view returns (bool) {
        (bool success, bytes memory data) = registry.staticcall(
            abi.encodeWithSignature("ownerOf(uint256)", tokenId)
        );
        return success && abi.decode(data, (address)) == user;
    }

    function _isValidLabel(string calldata label) internal pure returns (bool) {
        bytes memory b = bytes(label);
        if (b.length < 1 || b.length > 63) return false;

        for (uint256 i = 0; i < b.length; i++) {
            bytes1 char = b[i];
            bool isLower = (char >= 0x61 && char <= 0x7A);
            bool isDigit = (char >= 0x30 && char <= 0x39);
            bool isHyphen = (char == 0x2D);

            if (!isLower && !isDigit && !isHyphen) return false;
            if (isHyphen && (i == 0 || i == b.length - 1)) return false;
        }
        return true;
    }
}
