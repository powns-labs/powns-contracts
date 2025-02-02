// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TeamVesting
 * @notice Vesting contract for team tokens
 * @dev 1 year cliff + 3 years linear vesting
 */
contract TeamVesting is Ownable {
    using SafeERC20 for IERC20;

    // ============ Constants ============
    
    /// @notice Cliff duration: 1 year
    uint256 public constant CLIFF_DURATION = 365 days;
    
    /// @notice Vesting duration: 3 years (after cliff)
    uint256 public constant VESTING_DURATION = 3 * 365 days;
    
    /// @notice Total vesting period: 4 years
    uint256 public constant TOTAL_DURATION = CLIFF_DURATION + VESTING_DURATION;

    // ============ Storage ============
    
    /// @notice Token being vested
    IERC20 public token;
    
    /// @notice Beneficiary address
    address public beneficiary;
    
    /// @notice Vesting start time
    uint256 public startTime;
    
    /// @notice Total tokens allocated
    uint256 public totalAllocation;
    
    /// @notice Tokens already released
    uint256 public released;

    // ============ Events ============
    
    event TokensReleased(address indexed beneficiary, uint256 amount);
    event BeneficiaryChanged(address indexed oldBeneficiary, address indexed newBeneficiary);

    // ============ Errors ============
    
    error CliffNotReached();
    error NoTokensToRelease();
    error ZeroAddress();

    // ============ Constructor ============
    
    constructor(
        address _token,
        address _beneficiary,
        uint256 _startTime
    ) Ownable(msg.sender) {
        if (_token == address(0) || _beneficiary == address(0)) revert ZeroAddress();
        
        token = IERC20(_token);
        beneficiary = _beneficiary;
        startTime = _startTime;
    }

    // ============ Vesting Functions ============
    
    /**
     * @notice Release vested tokens to beneficiary
     */
    function release() external {
        uint256 releasable = vestedAmount() - released;
        if (releasable == 0) revert NoTokensToRelease();
        
        released += releasable;
        token.safeTransfer(beneficiary, releasable);
        
        emit TokensReleased(beneficiary, releasable);
    }

    /**
     * @notice Calculate vested amount at current time
     */
    function vestedAmount() public view returns (uint256) {
        uint256 total = totalAllocation;
        if (total == 0) {
            total = token.balanceOf(address(this)) + released;
        }
        
        return _vestedAmount(total, block.timestamp);
    }

    function _vestedAmount(uint256 total, uint256 timestamp) internal view returns (uint256) {
        if (timestamp < startTime + CLIFF_DURATION) {
            return 0; // Cliff not reached
        }
        
        if (timestamp >= startTime + TOTAL_DURATION) {
            return total; // Fully vested
        }
        
        // Linear vesting after cliff
        uint256 timeAfterCliff = timestamp - (startTime + CLIFF_DURATION);
        return (total * timeAfterCliff) / VESTING_DURATION;
    }

    /**
     * @notice Get releasable amount
     */
    function releasable() external view returns (uint256) {
        return vestedAmount() - released;
    }

    /**
     * @notice Get vesting schedule info
     */
    function getVestingInfo() external view returns (
        uint256 _totalAllocation,
        uint256 _released,
        uint256 _releasable,
        uint256 _cliffEnd,
        uint256 _vestingEnd
    ) {
        _totalAllocation = totalAllocation > 0 ? totalAllocation : token.balanceOf(address(this));
        _released = released;
        _releasable = vestedAmount() - released;
        _cliffEnd = startTime + CLIFF_DURATION;
        _vestingEnd = startTime + TOTAL_DURATION;
    }

    // ============ Admin ============
    
    /**
     * @notice Change beneficiary (for team member changes)
     */
    function setBeneficiary(address _newBeneficiary) external onlyOwner {
        if (_newBeneficiary == address(0)) revert ZeroAddress();
        
        address oldBeneficiary = beneficiary;
        beneficiary = _newBeneficiary;
        
        emit BeneficiaryChanged(oldBeneficiary, _newBeneficiary);
    }
}
