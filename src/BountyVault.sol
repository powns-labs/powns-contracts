// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IBountyVault} from "./interfaces/IBountyVault.sol";
import {IPoWNSRegistry} from "./interfaces/IPoWNSRegistry.sol";

/**
 * @title BountyVault
 * @notice Manages bounties for outsourced PoW mining
 * @dev Users post bounties, miners claim by submitting valid PoW
 */
contract BountyVault is IBountyVault, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // ============ Storage ============
    
    /// @notice Registry contract
    IPoWNSRegistry public registry;
    
    /// @notice Bounty storage
    mapping(bytes32 => Bounty) public bounties;
    
    /// @notice Bounties by owner
    mapping(address => bytes32[]) private _ownerBounties;
    
    /// @notice Active bounty list
    bytes32[] private _activeBounties;
    
    /// @notice Active bounty index (for efficient removal)
    mapping(bytes32 => uint256) private _activeBountyIndex;
    
    /// @notice Protocol fee (basis points, e.g., 250 = 2.5%)
    uint256 public protocolFeeBps;
    
    /// @notice Fee recipient
    address public feeRecipient;
    
    /// @notice Bounty counter for unique IDs
    uint256 private _bountyCounter;

    // ============ Errors ============
    
    error InvalidDeadline();
    error InvalidAmount();
    error BountyNotFound();
    error BountyExpired();
    error BountyNotExpired();
    error AlreadyClaimed();
    error AlreadyCancelled();
    error NotBountyOwner();
    error NameHashMismatch();
    error DifficultyTooHigh();
    error TransferFailed();

    // ============ Constructor ============
    
    constructor(
        address _registry,
        uint256 _protocolFeeBps,
        address _feeRecipient
    ) Ownable(msg.sender) {
        registry = IPoWNSRegistry(_registry);
        protocolFeeBps = _protocolFeeBps;
        feeRecipient = _feeRecipient;
    }

    // ============ Bounty Creation ============
    
    /**
     * @notice Create a bounty for mining a domain
     * @param nameHash keccak256 of the desired domain name
     * @param token Payment token (address(0) for ETH)
     * @param amount Bounty amount
     * @param deadline Expiration timestamp
     * @param minYears Minimum registration years
     * @param maxDifficulty Maximum acceptable difficulty bits
     */
    function createBounty(
        bytes32 nameHash,
        address token,
        uint256 amount,
        uint256 deadline,
        uint8 minYears,
        uint256 maxDifficulty
    ) external payable nonReentrant returns (bytes32 bountyId) {
        if (deadline <= block.timestamp) revert InvalidDeadline();
        if (amount == 0) revert InvalidAmount();
        
        // Generate unique bounty ID
        bountyId = keccak256(abi.encodePacked(
            msg.sender,
            nameHash,
            block.timestamp,
            _bountyCounter++
        ));
        
        // Transfer funds
        if (token == address(0)) {
            if (msg.value < amount) revert InvalidAmount();
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }
        
        // Store bounty
        bounties[bountyId] = Bounty({
            nameHash: nameHash,
            owner: msg.sender,
            token: token,
            amount: amount,
            deadline: deadline,
            minYears: minYears,
            maxDifficulty: maxDifficulty,
            claimed: false,
            cancelled: false
        });
        
        // Add to tracking arrays
        _ownerBounties[msg.sender].push(bountyId);
        _activeBountyIndex[bountyId] = _activeBounties.length;
        _activeBounties.push(bountyId);
        
        emit BountyCreated(bountyId, nameHash, msg.sender, token, amount, deadline);
        
        // Refund excess ETH
        if (token == address(0) && msg.value > amount) {
            (bool success, ) = msg.sender.call{value: msg.value - amount}("");
            if (!success) revert TransferFailed();
        }
    }

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
    ) external nonReentrant {
        Bounty storage bounty = bounties[bountyId];
        
        // Validate bounty state
        if (bounty.owner == address(0)) revert BountyNotFound();
        if (bounty.claimed) revert AlreadyClaimed();
        if (bounty.cancelled) revert AlreadyCancelled();
        if (block.timestamp > bounty.deadline) revert BountyExpired();
        
        // Verify name matches
        bytes32 computedHash = keccak256(bytes(name));
        if (computedHash != bounty.nameHash) revert NameHashMismatch();
        
        // Check difficulty
        uint256 currentDifficulty = registry.getDifficulty(name);
        if (currentDifficulty > bounty.maxDifficulty) revert DifficultyTooHigh();
        
        // Verify PoW and register domain via registry
        // The miner is msg.sender, owner is bounty.owner
        registry.register{value: 0}(
            name,
            bounty.owner,
            msg.sender,
            nonce,
            bounty.minYears
        );
        
        // Mark as claimed
        bounty.claimed = true;
        _removeFromActive(bountyId);
        
        // Calculate fees
        uint256 fee = (bounty.amount * protocolFeeBps) / 10000;
        uint256 minerReward = bounty.amount - fee;
        
        // Pay miner
        if (bounty.token == address(0)) {
            (bool success, ) = msg.sender.call{value: minerReward}("");
            if (!success) revert TransferFailed();
            if (fee > 0) {
                (success, ) = feeRecipient.call{value: fee}("");
                if (!success) revert TransferFailed();
            }
        } else {
            IERC20(bounty.token).safeTransfer(msg.sender, minerReward);
            if (fee > 0) {
                IERC20(bounty.token).safeTransfer(feeRecipient, fee);
            }
        }
        
        emit BountyClaimed(bountyId, msg.sender, name, minerReward);
    }

    /**
     * @notice Cancel a bounty (only before claim)
     */
    function cancelBounty(bytes32 bountyId) external nonReentrant {
        Bounty storage bounty = bounties[bountyId];
        
        if (bounty.owner != msg.sender) revert NotBountyOwner();
        if (bounty.claimed) revert AlreadyClaimed();
        if (bounty.cancelled) revert AlreadyCancelled();
        
        bounty.cancelled = true;
        _removeFromActive(bountyId);
        
        // Refund
        if (bounty.token == address(0)) {
            (bool success, ) = msg.sender.call{value: bounty.amount}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(bounty.token).safeTransfer(msg.sender, bounty.amount);
        }
        
        emit BountyCancelled(bountyId, msg.sender, bounty.amount);
    }

    /**
     * @notice Withdraw expired bounty funds
     */
    function withdrawExpired(bytes32 bountyId) external nonReentrant {
        Bounty storage bounty = bounties[bountyId];
        
        if (bounty.owner != msg.sender) revert NotBountyOwner();
        if (bounty.claimed) revert AlreadyClaimed();
        if (bounty.cancelled) revert AlreadyCancelled();
        if (block.timestamp <= bounty.deadline) revert BountyNotExpired();
        
        bounty.cancelled = true; // Mark as cancelled to prevent double-withdraw
        _removeFromActive(bountyId);
        
        // Refund
        if (bounty.token == address(0)) {
            (bool success, ) = msg.sender.call{value: bounty.amount}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(bounty.token).safeTransfer(msg.sender, bounty.amount);
        }
        
        emit BountyCancelled(bountyId, msg.sender, bounty.amount);
    }

    // ============ View Functions ============
    
    function getBounty(bytes32 bountyId) external view returns (Bounty memory) {
        return bounties[bountyId];
    }
    
    function getBountiesByOwner(address owner) external view returns (bytes32[] memory) {
        return _ownerBounties[owner];
    }
    
    function getActiveBounties() external view returns (bytes32[] memory) {
        return _activeBounties;
    }
    
    function getActiveBountiesCount() external view returns (uint256) {
        return _activeBounties.length;
    }

    // ============ Internal ============
    
    function _removeFromActive(bytes32 bountyId) internal {
        uint256 index = _activeBountyIndex[bountyId];
        uint256 lastIndex = _activeBounties.length - 1;
        
        if (index != lastIndex) {
            bytes32 lastBountyId = _activeBounties[lastIndex];
            _activeBounties[index] = lastBountyId;
            _activeBountyIndex[lastBountyId] = index;
        }
        
        _activeBounties.pop();
        delete _activeBountyIndex[bountyId];
    }

    // ============ Admin ============
    
    function setRegistry(address _registry) external onlyOwner {
        registry = IPoWNSRegistry(_registry);
    }
    
    function setProtocolFee(uint256 _feeBps) external onlyOwner {
        require(_feeBps <= 1000, "Fee too high"); // Max 10%
        protocolFeeBps = _feeBps;
    }
    
    function setFeeRecipient(address _recipient) external onlyOwner {
        feeRecipient = _recipient;
    }

    // ============ Receive ETH ============
    
    receive() external payable {}
}
