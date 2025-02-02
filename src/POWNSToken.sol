// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title POWNSToken
 * @notice Native token for PoW Name Service
 * @dev Fixed supply of 1 billion tokens with mining rewards distribution
 */
contract POWNSToken is ERC20, ERC20Burnable, ERC20Permit, Ownable {
    // ============ Constants ============
    
    /// @notice Total supply: 1 billion tokens
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**18;
    
    /// @notice Mining rewards allocation: 40% = 400M
    uint256 public constant MINING_ALLOCATION = 400_000_000 * 10**18;
    
    /// @notice DAO Treasury allocation: 25% = 250M
    uint256 public constant DAO_ALLOCATION = 250_000_000 * 10**18;
    
    /// @notice Team allocation: 15% = 150M
    uint256 public constant TEAM_ALLOCATION = 150_000_000 * 10**18;
    
    /// @notice Early contributors: 10% = 100M
    uint256 public constant CONTRIBUTORS_ALLOCATION = 100_000_000 * 10**18;
    
    /// @notice Liquidity: 10% = 100M
    uint256 public constant LIQUIDITY_ALLOCATION = 100_000_000 * 10**18;
    
    /// @notice Halving period: 2 years in seconds
    uint256 public constant HALVING_PERIOD = 730 days;
    
    /// @notice Initial base reward per registration
    uint256 public constant INITIAL_BASE_REWARD = 1000 * 10**18; // 1000 POWNS
    
    /// @notice Base difficulty for reward calculation (16 bits)
    uint256 public constant BASE_DIFFICULTY = 16;

    // ============ Storage ============
    
    /// @notice Registry contract address
    address public registry;
    
    /// @notice Total tokens distributed as mining rewards
    uint256 public miningRewardsDistributed;
    
    /// @notice Deployment timestamp (for halving calculation)
    uint256 public deployedAt;
    
    /// @notice DAO Treasury address
    address public daoTreasury;
    
    /// @notice Team vesting address
    address public teamVesting;
    
    /// @notice Whether initial distribution has been done
    bool public initialDistributionDone;

    // ============ Events ============
    
    event MiningReward(address indexed miner, uint256 amount, uint256 difficulty);
    event InitialDistribution(address dao, address team, address contributors, address liquidity);

    // ============ Errors ============
    
    error OnlyRegistry();
    error MiningAllocationExhausted();
    error AlreadyDistributed();
    error ZeroAddress();

    // ============ Constructor ============
    
    constructor() 
        ERC20("PoWNS Token", "POWNS") 
        ERC20Permit("PoWNS Token")
        Ownable(msg.sender) 
    {
        deployedAt = block.timestamp;
    }

    // ============ Modifiers ============
    
    modifier onlyRegistry() {
        if (msg.sender != registry) revert OnlyRegistry();
        _;
    }

    // ============ Initial Distribution ============
    
    /**
     * @notice Perform initial token distribution
     * @param _daoTreasury DAO treasury address (receives 25%)
     * @param _teamVesting Team vesting contract (receives 15%)
     * @param _contributors Early contributors address (receives 10%)
     * @param _liquidity Liquidity pool address (receives 10%)
     */
    function distributeInitial(
        address _daoTreasury,
        address _teamVesting,
        address _contributors,
        address _liquidity
    ) external onlyOwner {
        if (initialDistributionDone) revert AlreadyDistributed();
        if (_daoTreasury == address(0) || _teamVesting == address(0)) revert ZeroAddress();
        if (_contributors == address(0) || _liquidity == address(0)) revert ZeroAddress();
        
        initialDistributionDone = true;
        daoTreasury = _daoTreasury;
        teamVesting = _teamVesting;
        
        // Mint to recipients
        _mint(_daoTreasury, DAO_ALLOCATION);
        _mint(_teamVesting, TEAM_ALLOCATION);
        _mint(_contributors, CONTRIBUTORS_ALLOCATION);
        _mint(_liquidity, LIQUIDITY_ALLOCATION);
        
        emit InitialDistribution(_daoTreasury, _teamVesting, _contributors, _liquidity);
    }

    // ============ Mining Rewards ============
    
    /**
     * @notice Distribute mining reward to a miner
     * @param miner Address to receive reward
     * @param difficultyBits Difficulty of the mined domain
     * @dev Called by Registry on successful registration
     */
    function distributeMiningReward(
        address miner, 
        uint256 difficultyBits
    ) external onlyRegistry returns (uint256 reward) {
        reward = calculateReward(difficultyBits);
        
        // Check allocation limit
        if (miningRewardsDistributed + reward > MINING_ALLOCATION) {
            reward = MINING_ALLOCATION - miningRewardsDistributed;
            if (reward == 0) revert MiningAllocationExhausted();
        }
        
        miningRewardsDistributed += reward;
        _mint(miner, reward);
        
        emit MiningReward(miner, reward, difficultyBits);
    }

    /**
     * @notice Calculate reward based on difficulty and halving
     * @param difficultyBits The difficulty bits of the mined domain
     * @return reward The calculated reward amount
     */
    function calculateReward(uint256 difficultyBits) public view returns (uint256 reward) {
        // Base reward with halving
        uint256 halvings = (block.timestamp - deployedAt) / HALVING_PERIOD;
        uint256 baseReward = INITIAL_BASE_REWARD >> halvings; // Halve for each period
        
        if (baseReward == 0) {
            baseReward = 1; // Minimum 1 wei
        }
        
        // Difficulty multiplier: higher difficulty = higher reward
        // reward = baseReward * (difficulty / baseDifficulty)
        if (difficultyBits <= BASE_DIFFICULTY) {
            reward = baseReward;
        } else {
            reward = (baseReward * difficultyBits) / BASE_DIFFICULTY;
        }
    }

    /**
     * @notice Get current base reward (after halvings)
     */
    function getCurrentBaseReward() external view returns (uint256) {
        uint256 halvings = (block.timestamp - deployedAt) / HALVING_PERIOD;
        uint256 baseReward = INITIAL_BASE_REWARD >> halvings;
        return baseReward > 0 ? baseReward : 1;
    }

    /**
     * @notice Get number of halvings that have occurred
     */
    function getHalvings() external view returns (uint256) {
        return (block.timestamp - deployedAt) / HALVING_PERIOD;
    }

    /**
     * @notice Get remaining mining allocation
     */
    function remainingMiningAllocation() external view returns (uint256) {
        return MINING_ALLOCATION - miningRewardsDistributed;
    }

    // ============ Admin ============
    
    /**
     * @notice Set the registry address (one-time)
     */
    function setRegistry(address _registry) external onlyOwner {
        if (_registry == address(0)) revert ZeroAddress();
        registry = _registry;
    }
}
