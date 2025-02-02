// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title POWNSStaking
 * @notice Stake $POWNS tokens to earn protocol revenue and governance power
 * @dev Time-weighted staking with voting power multipliers
 */
contract POWNSStaking is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // ============ Structs ============
    
    struct StakeInfo {
        uint256 amount;           // Staked amount
        uint256 stakedAt;         // Stake start timestamp
        uint256 rewardDebt;       // Reward debt for accurate reward calculation
        uint256 pendingRewards;   // Unclaimed rewards
    }

    // ============ Constants ============
    
    /// @notice Minimum stake duration for withdrawal
    uint256 public constant MIN_STAKE_DURATION = 7 days;
    
    /// @notice Time multiplier thresholds (in seconds)
    uint256 public constant TIER_1_DURATION = 30 days;   // 1.25x
    uint256 public constant TIER_2_DURATION = 180 days;  // 1.5x
    uint256 public constant TIER_3_DURATION = 365 days;  // 2.0x
    
    /// @notice Multipliers (scaled by 100)
    uint256 public constant TIER_0_MULTIPLIER = 100;  // 1.0x
    uint256 public constant TIER_1_MULTIPLIER = 125;  // 1.25x
    uint256 public constant TIER_2_MULTIPLIER = 150;  // 1.5x
    uint256 public constant TIER_3_MULTIPLIER = 200;  // 2.0x

    // ============ Storage ============
    
    /// @notice POWNS token
    IERC20 public pownsToken;
    
    /// @notice Total staked tokens
    uint256 public totalStaked;
    
    /// @notice Accumulated rewards per share (scaled by 1e18)
    uint256 public accRewardPerShare;
    
    /// @notice Last reward distribution timestamp
    uint256 public lastRewardTime;
    
    /// @notice Pending rewards to distribute
    uint256 public pendingRewardsPool;
    
    /// @notice User stakes
    mapping(address => StakeInfo) public stakes;
    
    /// @notice Supported reward tokens (ETH, etc.)
    address[] public rewardTokens;
    mapping(address => bool) public isRewardToken;
    mapping(address => uint256) public accRewardPerShareByToken;

    // ============ Events ============
    
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event RewardsDeposited(address indexed token, uint256 amount);

    // ============ Errors ============
    
    error ZeroAmount();
    error InsufficientStake();
    error StakeTooShort();
    error NoRewards();
    error TransferFailed();

    // ============ Constructor ============
    
    constructor(address _pownsToken) Ownable(msg.sender) {
        pownsToken = IERC20(_pownsToken);
        lastRewardTime = block.timestamp;
    }

    // ============ Staking Functions ============
    
    /**
     * @notice Stake POWNS tokens
     * @param amount Amount to stake
     */
    function stake(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        
        _updateRewards();
        
        StakeInfo storage userStake = stakes[msg.sender];
        
        // Claim pending rewards first
        if (userStake.amount > 0) {
            uint256 pending = _calculatePendingRewards(msg.sender);
            if (pending > 0) {
                userStake.pendingRewards += pending;
            }
        }
        
        // Transfer tokens
        pownsToken.safeTransferFrom(msg.sender, address(this), amount);
        
        // Update stake
        userStake.amount += amount;
        userStake.stakedAt = block.timestamp;
        userStake.rewardDebt = (userStake.amount * accRewardPerShare) / 1e18;
        
        totalStaked += amount;
        
        emit Staked(msg.sender, amount);
    }

    /**
     * @notice Unstake POWNS tokens
     * @param amount Amount to unstake
     */
    function unstake(uint256 amount) external nonReentrant {
        StakeInfo storage userStake = stakes[msg.sender];
        
        if (amount == 0) revert ZeroAmount();
        if (userStake.amount < amount) revert InsufficientStake();
        if (block.timestamp < userStake.stakedAt + MIN_STAKE_DURATION) revert StakeTooShort();
        
        _updateRewards();
        
        // Calculate and store pending rewards
        uint256 pending = _calculatePendingRewards(msg.sender);
        if (pending > 0) {
            userStake.pendingRewards += pending;
        }
        
        // Update stake
        userStake.amount -= amount;
        userStake.rewardDebt = (userStake.amount * accRewardPerShare) / 1e18;
        
        totalStaked -= amount;
        
        // Transfer tokens back
        pownsToken.safeTransfer(msg.sender, amount);
        
        emit Unstaked(msg.sender, amount);
    }

    /**
     * @notice Claim accumulated rewards
     */
    function claimRewards() external nonReentrant {
        _updateRewards();
        
        StakeInfo storage userStake = stakes[msg.sender];
        
        uint256 pending = _calculatePendingRewards(msg.sender) + userStake.pendingRewards;
        if (pending == 0) revert NoRewards();
        
        userStake.pendingRewards = 0;
        userStake.rewardDebt = (userStake.amount * accRewardPerShare) / 1e18;
        
        // Transfer ETH rewards
        (bool success, ) = msg.sender.call{value: pending}("");
        if (!success) revert TransferFailed();
        
        emit RewardsClaimed(msg.sender, pending);
    }

    // ============ Reward Distribution ============
    
    /**
     * @notice Deposit rewards for distribution
     * @dev Called by protocol to distribute fees
     */
    function depositRewards() external payable {
        if (msg.value == 0) revert ZeroAmount();
        
        _updateRewards();
        
        if (totalStaked > 0) {
            accRewardPerShare += (msg.value * 1e18) / totalStaked;
        } else {
            pendingRewardsPool += msg.value;
        }
        
        emit RewardsDeposited(address(0), msg.value);
    }

    function _updateRewards() internal {
        if (totalStaked > 0 && pendingRewardsPool > 0) {
            accRewardPerShare += (pendingRewardsPool * 1e18) / totalStaked;
            pendingRewardsPool = 0;
        }
        lastRewardTime = block.timestamp;
    }

    function _calculatePendingRewards(address user) internal view returns (uint256) {
        StakeInfo storage userStake = stakes[user];
        if (userStake.amount == 0) return 0;
        
        uint256 rewards = (userStake.amount * accRewardPerShare) / 1e18 - userStake.rewardDebt;
        
        // Apply time multiplier
        uint256 multiplier = getTimeMultiplier(user);
        rewards = (rewards * multiplier) / 100;
        
        return rewards;
    }

    // ============ View Functions ============
    
    /**
     * @notice Get voting power for a user
     * @dev voting_power = staked_amount × time_multiplier
     */
    function getVotingPower(address user) external view returns (uint256) {
        StakeInfo storage userStake = stakes[user];
        uint256 multiplier = getTimeMultiplier(user);
        return (userStake.amount * multiplier) / 100;
    }

    /**
     * @notice Get time multiplier for a user
     */
    function getTimeMultiplier(address user) public view returns (uint256) {
        StakeInfo storage userStake = stakes[user];
        if (userStake.amount == 0) return TIER_0_MULTIPLIER;
        
        uint256 stakeDuration = block.timestamp - userStake.stakedAt;
        
        if (stakeDuration >= TIER_3_DURATION) {
            return TIER_3_MULTIPLIER; // 2.0x
        } else if (stakeDuration >= TIER_2_DURATION) {
            return TIER_2_MULTIPLIER; // 1.5x
        } else if (stakeDuration >= TIER_1_DURATION) {
            return TIER_1_MULTIPLIER; // 1.25x
        } else {
            return TIER_0_MULTIPLIER; // 1.0x
        }
    }

    /**
     * @notice Get pending rewards for a user
     */
    function pendingRewards(address user) external view returns (uint256) {
        StakeInfo storage userStake = stakes[user];
        return _calculatePendingRewards(user) + userStake.pendingRewards;
    }

    /**
     * @notice Get stake info for a user
     */
    function getStakeInfo(address user) external view returns (
        uint256 amount,
        uint256 stakedAt,
        uint256 votingPower,
        uint256 timeMultiplier,
        uint256 pending
    ) {
        StakeInfo storage userStake = stakes[user];
        amount = userStake.amount;
        stakedAt = userStake.stakedAt;
        timeMultiplier = getTimeMultiplier(user);
        votingPower = (amount * timeMultiplier) / 100;
        pending = _calculatePendingRewards(user) + userStake.pendingRewards;
    }

    // ============ Receive ETH ============
    
    receive() external payable {
        if (msg.value > 0) {
            _updateRewards();
            if (totalStaked > 0) {
                accRewardPerShare += (msg.value * 1e18) / totalStaked;
            } else {
                pendingRewardsPool += msg.value;
            }
            emit RewardsDeposited(address(0), msg.value);
        }
    }
}
