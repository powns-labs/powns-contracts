// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title DifficultyManager
 * @notice Manages difficulty adjustment using Dark Gravity Wave algorithm
 * @dev Based on Dash's DGW implementation
 */
abstract contract DifficultyManager {
    // ============ Constants ============
    
    /// @notice Minimum difficulty (16 leading zero bits)
    uint256 public constant MIN_DIFFICULTY_BITS = 16;
    
    /// @notice Maximum difficulty (240 leading zero bits)  
    uint256 public constant MAX_DIFFICULTY_BITS = 240;
    
    /// @notice Target interval between registrations (10 minutes)
    uint256 public constant TARGET_INTERVAL = 600;
    
    /// @notice Number of registrations to observe for DGW
    uint256 public constant DGW_WINDOW = 24;
    
    /// @notice Maximum single adjustment (+25%)
    uint256 public constant MAX_ADJUSTMENT = 125;
    
    /// @notice Minimum single adjustment (-25%)
    uint256 public constant MIN_ADJUSTMENT = 75;
    
    /// @notice Grace period duration (90 days)
    uint256 public constant GRACE_PERIOD = 90 days;
    
    /// @notice Auction duration until difficulty returns to base (~115 hours)
    uint256 public constant AUCTION_DURATION = 115 hours;

    // ============ Storage ============
    
    /// @notice Current global difficulty in bits
    uint256 public currentDifficultyBits;
    
    /// @notice Timestamps of recent registrations for DGW
    uint256[] public registrationTimestamps;
    
    /// @notice When auction started for a domain (nameHash => timestamp)
    mapping(bytes32 => uint256) public auctionStartTime;

    // ============ Events ============
    
    event DifficultyAdjusted(uint256 oldDifficulty, uint256 newDifficulty, uint256 timestamp);

    // ============ Constructor ============
    
    constructor() {
        currentDifficultyBits = MIN_DIFFICULTY_BITS;
    }

    // ============ Internal Functions ============
    
    /**
     * @notice Record a new registration and adjust difficulty
     */
    function _recordRegistration() internal {
        registrationTimestamps.push(block.timestamp);
        
        // Only adjust after we have enough samples
        if (registrationTimestamps.length >= DGW_WINDOW) {
            _adjustDifficulty();
        }
    }

    /**
     * @notice Dark Gravity Wave difficulty adjustment
     */
    function _adjustDifficulty() internal {
        uint256 len = registrationTimestamps.length;
        if (len < DGW_WINDOW) return;
        
        // Calculate actual average interval
        uint256 oldest = registrationTimestamps[len - DGW_WINDOW];
        uint256 newest = registrationTimestamps[len - 1];
        uint256 actualInterval = (newest - oldest) / (DGW_WINDOW - 1);
        
        // Prevent division by zero
        if (actualInterval == 0) actualInterval = 1;
        
        // Calculate adjustment ratio (scaled by 100)
        // adjustment = TARGET_INTERVAL / actualInterval
        uint256 adjustmentRatio = (TARGET_INTERVAL * 100) / actualInterval;
        
        // Clamp to ±25%
        if (adjustmentRatio > MAX_ADJUSTMENT) {
            adjustmentRatio = MAX_ADJUSTMENT;
        } else if (adjustmentRatio < MIN_ADJUSTMENT) {
            adjustmentRatio = MIN_ADJUSTMENT;
        }
        
        // Apply adjustment
        uint256 oldDifficulty = currentDifficultyBits;
        uint256 newDifficulty = (currentDifficultyBits * adjustmentRatio) / 100;
        
        // Enforce floor and ceiling
        if (newDifficulty < MIN_DIFFICULTY_BITS) {
            newDifficulty = MIN_DIFFICULTY_BITS;
        } else if (newDifficulty > MAX_DIFFICULTY_BITS) {
            newDifficulty = MAX_DIFFICULTY_BITS;
        }
        
        currentDifficultyBits = newDifficulty;
        
        emit DifficultyAdjusted(oldDifficulty, newDifficulty, block.timestamp);
    }

    /**
     * @notice Calculate difficulty bits for a domain name
     * @param name The domain name
     * @return difficultyBits The total difficulty bits
     */
    function _calculateDifficultyBits(string memory name) internal view returns (uint256) {
        uint256 baseBits = currentDifficultyBits;
        uint256 lengthWeight = _getLengthWeight(bytes(name).length);
        uint256 charsetWeight = _getCharsetWeight(name);
        
        uint256 totalBits = baseBits + lengthWeight + charsetWeight;
        
        // Enforce ceiling
        if (totalBits > MAX_DIFFICULTY_BITS) {
            totalBits = MAX_DIFFICULTY_BITS;
        }
        
        return totalBits;
    }

    /**
     * @notice Get length-based difficulty weight
     */
    function _getLengthWeight(uint256 length) internal pure returns (uint256) {
        if (length <= 3) return 32;
        if (length == 4) return 24;
        if (length == 5) return 16;
        if (length == 6) return 8;
        return 0; // 7+ characters
    }

    /**
     * @notice Get charset-based difficulty weight
     * @dev +8 for numeric only, +4 for alphabetic only, +0 for mixed
     */
    function _getCharsetWeight(string memory name) internal pure returns (uint256) {
        bytes memory b = bytes(name);
        bool hasDigit = false;
        bool hasLetter = false;
        
        for (uint256 i = 0; i < b.length; i++) {
            bytes1 char = b[i];
            if (char >= 0x30 && char <= 0x39) {
                hasDigit = true;
            } else if ((char >= 0x41 && char <= 0x5A) || (char >= 0x61 && char <= 0x7A)) {
                hasLetter = true;
            }
        }
        
        if (hasDigit && !hasLetter) return 8;  // Numeric only
        if (hasLetter && !hasDigit) return 4;  // Alphabetic only
        return 0; // Mixed
    }

    /**
     * @notice Convert difficulty bits to target threshold
     * @dev target = 2^(256 - difficultyBits)
     */
    function _bitsToTarget(uint256 bits) internal pure returns (uint256) {
        require(bits <= 256, "Invalid difficulty bits");
        if (bits >= 256) return 0;
        return type(uint256).max >> bits;
    }

    /**
     * @notice Calculate renewal difficulty multiplier
     * @param additionalYears Years to add (1-10)
     * @return multiplier Scaled by 100 (e.g., 110 = 1.1x)
     */
    function _getRenewalMultiplier(uint8 additionalYears) internal pure returns (uint256) {
        // difficulty = base × (1 + 0.1 × years)
        // Scaled by 100: 100 + 10 × years
        return 100 + (10 * uint256(additionalYears));
    }

    /**
     * @notice Calculate Dutch auction difficulty for expired domain
     * @param nameHash The domain's nameHash
     * @param baseDifficultyBits Base difficulty for this name
     * @return Current difficulty bits during auction
     */
    function _getAuctionDifficulty(
        bytes32 nameHash, 
        uint256 baseDifficultyBits
    ) internal view returns (uint256) {
        uint256 startTime = auctionStartTime[nameHash];
        if (startTime == 0) return baseDifficultyBits;
        
        uint256 elapsed = block.timestamp - startTime;
        uint256 hoursElapsed = elapsed / 1 hours;
        
        // Starts at 10x (1000), decreases 2% per hour (20 per hour)
        // After 45 hours: 1000 - 45*20 = 100 (1x)
        uint256 multiplier;
        if (hoursElapsed * 20 >= 900) {
            multiplier = 100; // Minimum 1x
        } else {
            multiplier = 1000 - (hoursElapsed * 20);
        }
        
        // Apply multiplier (additively to bits, not multiplicatively)
        // Higher multiplier = harder = more bits
        // 1000 = 10x base, 100 = 1x base
        // Convert to additive bits: log2(multiplier/100) ≈ multiplier/100 bits extra
        uint256 extraBits = (multiplier - 100) / 10; // Simplified: 900 -> 90 extra bits at start
        
        uint256 totalBits = baseDifficultyBits + extraBits;
        if (totalBits > MAX_DIFFICULTY_BITS) {
            totalBits = MAX_DIFFICULTY_BITS;
        }
        
        return totalBits;
    }

    // ============ View Functions ============
    
    /**
     * @notice Get current target for a domain
     */
    function getTarget(string memory name) public view returns (uint256) {
        uint256 bits = _calculateDifficultyBits(name);
        return _bitsToTarget(bits);
    }
    
    /**
     * @notice Get difficulty bits for a domain
     */
    function getDifficultyBits(string memory name) public view returns (uint256) {
        return _calculateDifficultyBits(name);
    }
}
