// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IPoWNSVerifier.sol";

/**
 * @title PoWNSVerifier
 * @notice Verifies Proof of Work for domain registration
 * @dev hash = SHA256(name || owner || miner || nonce || chainId || registryAddress)
 */
contract PoWNSVerifier is IPoWNSVerifier {
    address public immutable registry;

    constructor(address _registry) {
        registry = _registry;
    }

    /**
     * @notice Compute the hash for a PoW attempt
     * @dev Uses SHA256 for efficient on-chain verification (~60 gas)
     */
    function computeHash(
        string calldata name,
        address owner,
        address miner,
        uint256 nonce
    ) public view returns (bytes32) {
        return sha256(
            abi.encodePacked(
                name,
                owner,
                miner,
                nonce,
                block.chainid,
                registry
            )
        );
    }

    /**
     * @notice Verify a PoW submission
     * @param name The domain name
     * @param owner NFT recipient
     * @param miner Transaction submitter (bound in hash to prevent front-running)
     * @param nonce The nonce found by miner
     * @param target The target difficulty threshold
     * @return valid True if hash < target
     * @return hashValue The computed hash
     */
    function verify(
        string calldata name,
        address owner,
        address miner,
        uint256 nonce,
        uint256 target
    ) external view returns (bool valid, bytes32 hashValue) {
        hashValue = computeHash(name, owner, miner, nonce);
        valid = uint256(hashValue) < target;
    }
}
