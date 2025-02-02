// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {PoWNSRegistry} from "../src/PoWNSRegistry.sol";
import {PoWNSVerifier} from "../src/PoWNSVerifier.sol";
import {PoWNSResolver} from "../src/PoWNSResolver.sol";
import {BountyVault} from "../src/BountyVault.sol";
import {POWNSToken} from "../src/POWNSToken.sol";
import {POWNSStaking} from "../src/POWNSStaking.sol";
import {ProtocolFeeDistributor} from "../src/ProtocolFeeDistributor.sol";
import {TeamVesting} from "../src/TeamVesting.sol";
import {Marketplace} from "../src/Marketplace.sol";
import {DomainLeasing} from "../src/DomainLeasing.sol";

/**
 * @title DeployPoWNS
 * @notice Deploys all PoWNS contracts
 */
contract DeployPoWNS is Script {
    // Deployment config
    uint256 public constant MIN_DEPOSIT_PER_YEAR = 0.001 ether;
    uint256 public constant BOUNTY_PROTOCOL_FEE_BPS = 250; // 2.5%
    
    // Deployed contracts
    PoWNSRegistry public registry;
    PoWNSVerifier public verifier;
    PoWNSResolver public resolver;
    BountyVault public bountyVault;
    POWNSToken public pownsToken;
    POWNSStaking public staking;
    ProtocolFeeDistributor public feeDistributor;
    TeamVesting public teamVesting;
    Marketplace public marketplace;
    DomainLeasing public domainLeasing;
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying PoWNS contracts...");
        console.log("Deployer:", deployer);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy Registry (with placeholder verifier)
        registry = new PoWNSRegistry(address(0), MIN_DEPOSIT_PER_YEAR);
        console.log("Registry deployed:", address(registry));
        
        // 2. Deploy Verifier
        verifier = new PoWNSVerifier(address(registry));
        console.log("Verifier deployed:", address(verifier));
        
        // 3. Set verifier in registry
        registry.setVerifier(address(verifier));
        
        // 4. Deploy Resolver
        resolver = new PoWNSResolver(address(registry));
        console.log("Resolver deployed:", address(resolver));
        
        // 5. Deploy POWNS Token
        pownsToken = new POWNSToken();
        console.log("POWNS Token deployed:", address(pownsToken));
        
        // 6. Set registry in token
        pownsToken.setRegistry(address(registry));
        
        // 7. Deploy Staking
        staking = new POWNSStaking(address(pownsToken));
        console.log("Staking deployed:", address(staking));
        
        // 8. Deploy Fee Distributor
        feeDistributor = new ProtocolFeeDistributor(address(staking), deployer);
        console.log("Fee Distributor deployed:", address(feeDistributor));
        
        // 9. Deploy BountyVault
        bountyVault = new BountyVault(
            address(registry),
            BOUNTY_PROTOCOL_FEE_BPS,
            address(feeDistributor)
        );
        console.log("BountyVault deployed:", address(bountyVault));
        
        // 10. Deploy Team Vesting
        teamVesting = new TeamVesting(
            address(pownsToken),
            deployer, // Team beneficiary
            block.timestamp
        );
        console.log("Team Vesting deployed:", address(teamVesting));
        
        // 11. Deploy Marketplace
        marketplace = new Marketplace(address(registry), address(feeDistributor));
        console.log("Marketplace deployed:", address(marketplace));
        
        // 12. Deploy Domain Leasing
        domainLeasing = new DomainLeasing(
            address(registry),
            address(resolver),
            address(feeDistributor)
        );
        console.log("Domain Leasing deployed:", address(domainLeasing));
        
        vm.stopBroadcast();
        
        // Log summary
        console.log("\n=== Deployment Summary ===");
        console.log("Registry:", address(registry));
        console.log("Verifier:", address(verifier));
        console.log("Resolver:", address(resolver));
        console.log("POWNS Token:", address(pownsToken));
        console.log("Staking:", address(staking));
        console.log("Fee Distributor:", address(feeDistributor));
        console.log("BountyVault:", address(bountyVault));
        console.log("Team Vesting:", address(teamVesting));
        console.log("Marketplace:", address(marketplace));
        console.log("Domain Leasing:", address(domainLeasing));
    }
}

/**
 * @title InitializeTokenDistribution
 * @notice Performs initial token distribution
 */
contract InitializeTokenDistribution is Script {
    function run(
        address pownsToken,
        address daoTreasury,
        address teamVesting,
        address contributors,
        address liquidity
    ) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        POWNSToken token = POWNSToken(pownsToken);
        token.distributeInitial(daoTreasury, teamVesting, contributors, liquidity);
        
        console.log("Token distribution complete!");
        console.log("DAO Treasury:", daoTreasury);
        console.log("Team Vesting:", teamVesting);
        console.log("Contributors:", contributors);
        console.log("Liquidity:", liquidity);
        
        vm.stopBroadcast();
    }
}
