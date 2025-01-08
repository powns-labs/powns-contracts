// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPoWNSVerifier
 * @notice Interface for PoW verification
 */
interface IPoWNSVerifier {
    /**
     * @notice Verify a PoW submission
     * @param name The domain name
     * @param owner NFT recipient
     * @param miner Transaction submitter (bound in hash)
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
    ) external view returns (bool valid, bytes32 hashValue);

    /**
     * @notice Compute the hash for a PoW attempt
     * @dev hash = SHA256(name || owner || miner || nonce || chainId || registryAddress)
     */
    function computeHash(
        string calldata name,
        address owner,
        address miner,
        uint256 nonce
    ) external view returns (bytes32);
}
