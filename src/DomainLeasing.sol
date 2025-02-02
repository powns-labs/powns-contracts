// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IResolver} from "./interfaces/IResolver.sol";

/**
 * @title DomainLeasing
 * @notice Allows domain owners to lease their domains to tenants
 * @dev Tenants get temporary resolver control
 */
contract DomainLeasing is Ownable {
    // ============ Structs ============
    
    struct Lease {
        address owner;          // Domain owner
        address tenant;         // Current tenant
        uint256 pricePerMonth;  // Monthly rent in wei
        uint256 startTime;      // Lease start
        uint256 endTime;        // Lease end
        uint256 paidUntil;      // Paid up to this time
        bool active;
    }
    
    struct LeaseOffer {
        uint256 tokenId;
        address offeredTenant;
        uint256 pricePerMonth;
        uint256 months;
        uint256 expiresAt;
        bool active;
    }

    // ============ Storage ============
    
    /// @notice Registry contract
    address public registry;
    
    /// @notice Resolver contract
    IResolver public resolver;
    
    /// @notice Active leases by tokenId
    mapping(uint256 => Lease) public leases;
    
    /// @notice Lease offers by offerId
    mapping(bytes32 => LeaseOffer) public leaseOffers;
    
    /// @notice Whether a tenant has resolver access
    mapping(uint256 => mapping(address => bool)) public hasResolverAccess;
    
    /// @notice Protocol fee (5%)
    uint256 public constant PROTOCOL_FEE_BPS = 500;
    uint256 public constant BASIS_POINTS = 10000;
    
    /// @notice Fee recipient
    address public feeRecipient;

    // ============ Events ============
    
    event LeaseCreated(uint256 indexed tokenId, address indexed owner, uint256 pricePerMonth);
    event LeaseStarted(uint256 indexed tokenId, address indexed tenant, uint256 months);
    event LeaseExtended(uint256 indexed tokenId, address indexed tenant, uint256 newEndTime);
    event LeaseTerminated(uint256 indexed tokenId, address indexed tenant);
    event LeaseOfferCreated(bytes32 indexed offerId, uint256 indexed tokenId, address tenant, uint256 months);

    // ============ Errors ============
    
    error NotOwner();
    error LeaseNotActive();
    error LeaseAlreadyActive();
    error NotTenant();
    error InsufficientPayment();
    error LeaseNotEnded();
    error TransferFailed();
    error OfferExpired();
    error OfferNotFound();

    // ============ Constructor ============
    
    constructor(address _registry, address _resolver, address _feeRecipient) Ownable(msg.sender) {
        registry = _registry;
        resolver = IResolver(_resolver);
        feeRecipient = _feeRecipient;
    }

    // ============ Owner Functions ============
    
    /**
     * @notice Create a lease listing for a domain
     */
    function createLease(
        uint256 tokenId,
        uint256 pricePerMonth
    ) external {
        // Verify ownership via registry
        (bool success, bytes memory data) = registry.call(
            abi.encodeWithSignature("ownerOf(uint256)", tokenId)
        );
        require(success && abi.decode(data, (address)) == msg.sender, "Not owner");
        
        if (leases[tokenId].active && leases[tokenId].tenant != address(0)) {
            revert LeaseAlreadyActive();
        }
        
        leases[tokenId] = Lease({
            owner: msg.sender,
            tenant: address(0),
            pricePerMonth: pricePerMonth,
            startTime: 0,
            endTime: 0,
            paidUntil: 0,
            active: true
        });
        
        emit LeaseCreated(tokenId, msg.sender, pricePerMonth);
    }

    /**
     * @notice Rent a domain
     */
    function rent(uint256 tokenId, uint256 months) external payable {
        Lease storage lease = leases[tokenId];
        if (!lease.active) revert LeaseNotActive();
        if (lease.tenant != address(0)) revert LeaseAlreadyActive();
        
        uint256 totalCost = lease.pricePerMonth * months;
        if (msg.value < totalCost) revert InsufficientPayment();
        
        // Update lease
        lease.tenant = msg.sender;
        lease.startTime = block.timestamp;
        lease.endTime = block.timestamp + (months * 30 days);
        lease.paidUntil = lease.endTime;
        
        // Grant resolver access
        hasResolverAccess[tokenId][msg.sender] = true;
        
        // Distribute payment
        uint256 fee = (totalCost * PROTOCOL_FEE_BPS) / BASIS_POINTS;
        uint256 ownerAmount = totalCost - fee;
        
        (bool success1, ) = lease.owner.call{value: ownerAmount}("");
        (bool success2, ) = feeRecipient.call{value: fee}("");
        if (!success1 || !success2) revert TransferFailed();
        
        // Refund excess
        if (msg.value > totalCost) {
            (bool success3, ) = msg.sender.call{value: msg.value - totalCost}("");
            if (!success3) revert TransferFailed();
        }
        
        emit LeaseStarted(tokenId, msg.sender, months);
    }

    /**
     * @notice Extend an existing lease
     */
    function extendLease(uint256 tokenId, uint256 additionalMonths) external payable {
        Lease storage lease = leases[tokenId];
        if (lease.tenant != msg.sender) revert NotTenant();
        
        uint256 totalCost = lease.pricePerMonth * additionalMonths;
        if (msg.value < totalCost) revert InsufficientPayment();
        
        // Extend from current end time or now (whichever is later)
        uint256 extendFrom = lease.endTime > block.timestamp ? lease.endTime : block.timestamp;
        lease.endTime = extendFrom + (additionalMonths * 30 days);
        lease.paidUntil = lease.endTime;
        
        // Distribute payment
        uint256 fee = (totalCost * PROTOCOL_FEE_BPS) / BASIS_POINTS;
        uint256 ownerAmount = totalCost - fee;
        
        (bool success1, ) = lease.owner.call{value: ownerAmount}("");
        (bool success2, ) = feeRecipient.call{value: fee}("");
        if (!success1 || !success2) revert TransferFailed();
        
        emit LeaseExtended(tokenId, msg.sender, lease.endTime);
    }

    /**
     * @notice Terminate lease early (tenant)
     */
    function terminateLease(uint256 tokenId) external {
        Lease storage lease = leases[tokenId];
        if (lease.tenant != msg.sender) revert NotTenant();
        
        // Revoke resolver access
        hasResolverAccess[tokenId][msg.sender] = false;
        
        // Calculate refund (prorated)
        uint256 refund = 0;
        if (block.timestamp < lease.paidUntil) {
            uint256 remainingTime = lease.paidUntil - block.timestamp;
            uint256 totalPaidTime = lease.paidUntil - lease.startTime;
            uint256 totalPaid = (totalPaidTime / 30 days) * lease.pricePerMonth;
            refund = (totalPaid * remainingTime) / totalPaidTime;
        }
        
        // Clear tenant
        address tenant = lease.tenant;
        lease.tenant = address(0);
        lease.endTime = block.timestamp;
        
        // Send refund
        if (refund > 0) {
            (bool success, ) = tenant.call{value: refund}("");
            if (!success) revert TransferFailed();
        }
        
        emit LeaseTerminated(tokenId, tenant);
    }

    /**
     * @notice Cleanup expired lease
     */
    function endExpiredLease(uint256 tokenId) external {
        Lease storage lease = leases[tokenId];
        if (block.timestamp < lease.endTime) revert LeaseNotEnded();
        
        if (lease.tenant != address(0)) {
            hasResolverAccess[tokenId][lease.tenant] = false;
            emit LeaseTerminated(tokenId, lease.tenant);
            lease.tenant = address(0);
        }
    }

    // ============ View Functions ============
    
    function getLease(uint256 tokenId) external view returns (Lease memory) {
        return leases[tokenId];
    }
    
    function canSetResolver(uint256 tokenId, address user) external view returns (bool) {
        Lease storage lease = leases[tokenId];
        
        // Owner can always set (if no active tenant)
        if (lease.tenant == address(0)) {
            return true; // Defer to registry for ownership check
        }
        
        // Active tenant can set
        if (lease.tenant == user && block.timestamp <= lease.endTime) {
            return hasResolverAccess[tokenId][user];
        }
        
        return false;
    }
    
    function isLeaseActive(uint256 tokenId) external view returns (bool) {
        Lease storage lease = leases[tokenId];
        return lease.active && lease.tenant != address(0) && block.timestamp <= lease.endTime;
    }

    // ============ Admin ============
    
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        feeRecipient = _feeRecipient;
    }
}
