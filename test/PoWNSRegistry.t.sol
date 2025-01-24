// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PoWNSRegistry} from "../src/PoWNSRegistry.sol";
import {PoWNSVerifier} from "../src/PoWNSVerifier.sol";
import {IPoWNSVerifier} from "../src/interfaces/IPoWNSVerifier.sol";

/**
 * @title MockVerifier
 * @notice Always returns valid for testing purposes
 */
contract MockVerifier is IPoWNSVerifier {
    address public registry;
    
    constructor(address _registry) {
        registry = _registry;
    }
    
    function verify(
        string calldata,
        address,
        address,
        uint256,
        uint256
    ) external pure returns (bool valid, bytes32 hashValue) {
        return (true, bytes32(uint256(1)));
    }
    
    function computeHash(
        string calldata,
        address,
        address,
        uint256
    ) external pure returns (bytes32) {
        return bytes32(uint256(1));
    }
}

contract PoWNSRegistryTest is Test {
    PoWNSRegistry public registry;
    MockVerifier public mockVerifier;
    PoWNSVerifier public realVerifier;
    
    address public owner = address(0x1111);
    address public miner = address(0x2222);
    address public user = address(0x3333);
    
    uint256 public constant MIN_DEPOSIT_PER_YEAR = 0.001 ether;

    function setUp() public {
        // Deploy registry with placeholder
        registry = new PoWNSRegistry(address(0), MIN_DEPOSIT_PER_YEAR);
        
        // Deploy mock verifier for most tests
        mockVerifier = new MockVerifier(address(registry));
        registry.setVerifier(address(mockVerifier));
        
        // Also deploy real verifier for verification tests
        realVerifier = new PoWNSVerifier(address(registry));
        
        // Fund accounts
        vm.deal(owner, 10 ether);
        vm.deal(miner, 10 ether);
        vm.deal(user, 10 ether);
    }

    // ============ Difficulty Tests ============

    function test_DifficultyBits() public view {
        // Test length weights + charset weights
        // "abc" = 3 chars (+32) + alphabetic only (+4) = 16 + 32 + 4 = 52
        assertEq(registry.getDifficultyBits("abc"), 16 + 32 + 4);
        // "abcd" = 4 chars (+24) + alphabetic (+4) = 44
        assertEq(registry.getDifficultyBits("abcd"), 16 + 24 + 4);
        // "abcde" = 5 chars (+16) + alphabetic (+4) = 36
        assertEq(registry.getDifficultyBits("abcde"), 16 + 16 + 4);
        // "abcdef" = 6 chars (+8) + alphabetic (+4) = 28
        assertEq(registry.getDifficultyBits("abcdef"), 16 + 8 + 4);
        // "abcdefg" = 7+ chars (+0) + alphabetic (+4) = 20
        assertEq(registry.getDifficultyBits("abcdefg"), 16 + 4);
    }

    function test_DifficultyBitsCharset() public view {
        // Numeric only = +8
        assertEq(registry.getDifficultyBits("123456789"), 16 + 8);
        
        // Alphabetic only = +4
        assertEq(registry.getDifficultyBits("abcdefghi"), 16 + 4);
        
        // Mixed = +0
        assertEq(registry.getDifficultyBits("abc123def"), 16);
    }

    function test_Target() public view {
        uint256 target = registry.getTarget("testname");
        assertGt(target, 0);
        
        // Shorter name should have smaller target (higher difficulty)
        uint256 shortTarget = registry.getTarget("abc");
        assertLt(shortTarget, target);
    }

    // ============ PoW Verification Tests (using real verifier) ============

    function test_ComputeHash() public view {
        bytes32 hash = realVerifier.computeHash("test", owner, miner, 12345);
        assertNotEq(hash, bytes32(0));
        
        // Same inputs should produce same hash
        bytes32 hash2 = realVerifier.computeHash("test", owner, miner, 12345);
        assertEq(hash, hash2);
        
        // Different nonce should produce different hash
        bytes32 hash3 = realVerifier.computeHash("test", owner, miner, 12346);
        assertNotEq(hash, hash3);
    }

    function test_VerifyPoW() public view {
        // With a very high target (easy difficulty), any hash should pass
        uint256 easyTarget = type(uint256).max;
        (bool valid, bytes32 hash) = realVerifier.verify("test", owner, miner, 1, easyTarget);
        assertTrue(valid);
        assertNotEq(hash, bytes32(0));
    }

    function test_VerifyPoWFails() public view {
        // With a very low target (hard difficulty), should fail
        uint256 hardTarget = 1;
        (bool valid, ) = realVerifier.verify("test", owner, miner, 1, hardTarget);
        assertFalse(valid);
    }

    // ============ Registration Tests ============

    function test_NameValidation() public {
        // Name too short
        vm.expectRevert("Name too short");
        vm.prank(miner);
        registry.register{value: 0.001 ether}("ab", owner, miner, 1, 1);
    }

    function test_InitialState() public view {
        assertEq(registry.name(), "PoWNS");
        assertEq(registry.symbol(), "POWNS");
        assertEq(registry.minDepositPerYear(), MIN_DEPOSIT_PER_YEAR);
    }

    function test_ValidNameChars() public {
        assertTrue(registry.isAvailable("hello"));
        assertTrue(registry.isAvailable("hello-world"));
        assertTrue(registry.isAvailable("test123"));
        assertTrue(registry.isAvailable("validname"));
    }

    function test_RegisterDomain() public {
        string memory name = "testdomain";
        
        // Register with mock verifier (always passes PoW)
        vm.prank(miner);
        registry.register{value: 0.001 ether}(name, owner, miner, 12345, 1);
        
        // Verify registration
        assertEq(registry.ownerOf(name), owner);
        assertGt(registry.expiresAt(name), block.timestamp);
        assertFalse(registry.isAvailable(name));
    }

    function test_CannotRegisterTwice() public {
        string memory name = "testdomain";
        
        // First registration
        vm.prank(miner);
        registry.register{value: 0.001 ether}(name, owner, miner, 1, 1);
        
        // Second registration should fail
        vm.expectRevert("Domain not available");
        vm.prank(miner);
        registry.register{value: 0.001 ether}(name, user, miner, 2, 1);
    }

    function test_InsufficientDeposit() public {
        vm.expectRevert("Insufficient deposit");
        vm.prank(miner);
        registry.register{value: 0.0001 ether}("testname", owner, miner, 1, 1);
    }

    function test_RegisterMultipleYears() public {
        string memory name = "multiyear";
        uint256 deposit = 0.005 ether; // 5 years
        
        vm.prank(miner);
        registry.register{value: deposit}(name, owner, miner, 1, 5);
        
        // Should expire in ~5 years
        uint256 expires = registry.expiresAt(name);
        assertGt(expires, block.timestamp + 4 * 365 days);
        assertLt(expires, block.timestamp + 6 * 365 days);
    }

    // ============ Transfer Tests ============

    function test_TransferDomain() public {
        string memory name = "transfertest";
        
        // Register
        vm.prank(miner);
        registry.register{value: 0.001 ether}(name, owner, miner, 1, 1);
        
        // Get token ID
        bytes32 nameHash = keccak256(bytes(name));
        uint256 tokenId = registry.tokenIds(nameHash);
        
        // Transfer
        vm.prank(owner);
        registry.transferFrom(owner, user, tokenId);
        
        // Verify new owner
        assertEq(registry.ownerOf(name), user);
        assertEq(registry.ownerOf(tokenId), user);
    }

    function test_CannotTransferIfNotOwner() public {
        string memory name = "notmyname";
        
        vm.prank(miner);
        registry.register{value: 0.001 ether}(name, owner, miner, 1, 1);
        
        bytes32 nameHash = keccak256(bytes(name));
        uint256 tokenId = registry.tokenIds(nameHash);
        
        // Try to transfer as non-owner
        vm.expectRevert();
        vm.prank(user);
        registry.transferFrom(owner, user, tokenId);
    }

    // ============ Release Tests ============

    function test_ReleaseDomain() public {
        string memory name = "releasetest";
        uint256 deposit = 0.001 ether;
        
        // Register
        vm.prank(miner);
        registry.register{value: deposit}(name, owner, miner, 1, 1);
        
        uint256 ownerBalanceBefore = owner.balance;
        
        // Release
        vm.prank(owner);
        registry.release(name);
        
        // Verify released
        assertTrue(registry.isAvailable(name));
        assertEq(owner.balance, ownerBalanceBefore + deposit);
    }

    function test_CannotReleaseIfNotOwner() public {
        string memory name = "notmine";
        
        vm.prank(miner);
        registry.register{value: 0.001 ether}(name, owner, miner, 1, 1);
        
        vm.expectRevert("Not owner");
        vm.prank(user);
        registry.release(name);
    }

    // ============ State Tests ============

    function test_DomainState() public {
        string memory name = "statetest";
        
        // Initially available
        assertEq(uint256(registry.getState(name)), uint256(0)); // Available
        
        // Register
        vm.prank(miner);
        registry.register{value: 0.001 ether}(name, owner, miner, 1, 1);
        
        // Now active
        assertEq(uint256(registry.getState(name)), uint256(1)); // Active
    }

    function test_DomainExpired() public {
        string memory name = "expiretest";
        
        vm.prank(miner);
        registry.register{value: 0.001 ether}(name, owner, miner, 1, 1);
        
        // Warp past expiration
        vm.warp(block.timestamp + 366 days);
        
        // Should be in grace period
        assertEq(uint256(registry.getState(name)), uint256(3)); // GracePeriod
    }

    function test_DomainAuction() public {
        string memory name = "auctiontest";
        
        vm.prank(miner);
        registry.register{value: 0.001 ether}(name, owner, miner, 1, 1);
        
        // Warp past expiration + grace period
        vm.warp(block.timestamp + 366 days + 91 days);
        
        // Should be in auction
        assertEq(uint256(registry.getState(name)), uint256(4)); // Auction
    }
}
