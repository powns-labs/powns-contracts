// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {POWNSStaking} from "./POWNSStaking.sol";

/**
 * @title ProtocolFeeDistributor
 * @notice Collects and distributes protocol fees
 * @dev Revenue split: 50% Stakers, 30% DAO, 20% Burn
 */
contract ProtocolFeeDistributor is Ownable, ReentrancyGuard {
    // ============ Constants ============
    
    /// @notice Fee split percentages (basis points)
    uint256 public constant STAKERS_SHARE = 5000;  // 50%
    uint256 public constant DAO_SHARE = 3000;      // 30%
    uint256 public constant BURN_SHARE = 2000;     // 20%
    uint256 public constant BASIS_POINTS = 10000;  // 100%

    // ============ Storage ============
    
    /// @notice Staking contract
    POWNSStaking public staking;
    
    /// @notice DAO Treasury address
    address public daoTreasury;
    
    /// @notice Total fees collected
    uint256 public totalFeesCollected;
    
    /// @notice Total fees distributed to stakers
    uint256 public totalToStakers;
    
    /// @notice Total fees sent to DAO
    uint256 public totalToDao;
    
    /// @notice Total ETH burned (sent to 0xdead)
    uint256 public totalBurned;

    // ============ Events ============
    
    event FeesCollected(uint256 amount);
    event FeesDistributed(uint256 toStakers, uint256 toDao, uint256 burned);

    // ============ Errors ============
    
    error NoFeesToDistribute();
    error TransferFailed();
    error ZeroAddress();

    // ============ Constructor ============
    
    constructor(address _staking, address _daoTreasury) Ownable(msg.sender) {
        if (_staking == address(0) || _daoTreasury == address(0)) revert ZeroAddress();
        staking = POWNSStaking(payable(_staking));
        daoTreasury = _daoTreasury;
    }

    // ============ Fee Distribution ============
    
    /**
     * @notice Distribute accumulated fees
     */
    function distribute() external nonReentrant {
        uint256 balance = address(this).balance;
        if (balance == 0) revert NoFeesToDistribute();
        
        // Calculate shares
        uint256 toStakers = (balance * STAKERS_SHARE) / BASIS_POINTS;
        uint256 toDao = (balance * DAO_SHARE) / BASIS_POINTS;
        uint256 toBurn = balance - toStakers - toDao; // Remainder to burn
        
        // Update totals
        totalToStakers += toStakers;
        totalToDao += toDao;
        totalBurned += toBurn;
        
        // Send to staking for distribution
        if (toStakers > 0) {
            staking.depositRewards{value: toStakers}();
        }
        
        // Send to DAO
        if (toDao > 0) {
            (bool success, ) = daoTreasury.call{value: toDao}("");
            if (!success) revert TransferFailed();
        }
        
        // Burn (send to dead address)
        if (toBurn > 0) {
            (bool success, ) = address(0xdead).call{value: toBurn}("");
            if (!success) revert TransferFailed();
        }
        
        emit FeesDistributed(toStakers, toDao, toBurn);
    }

    /**
     * @notice Get pending distribution amounts
     */
    function getPendingDistribution() external view returns (
        uint256 total,
        uint256 toStakers,
        uint256 toDao,
        uint256 toBurn
    ) {
        total = address(this).balance;
        toStakers = (total * STAKERS_SHARE) / BASIS_POINTS;
        toDao = (total * DAO_SHARE) / BASIS_POINTS;
        toBurn = total - toStakers - toDao;
    }

    // ============ Admin ============
    
    function setDaoTreasury(address _daoTreasury) external onlyOwner {
        if (_daoTreasury == address(0)) revert ZeroAddress();
        daoTreasury = _daoTreasury;
    }
    
    function setStaking(address _staking) external onlyOwner {
        if (_staking == address(0)) revert ZeroAddress();
        staking = POWNSStaking(payable(_staking));
    }

    // ============ Receive ETH ============
    
    receive() external payable {
        totalFeesCollected += msg.value;
        emit FeesCollected(msg.value);
    }
}
