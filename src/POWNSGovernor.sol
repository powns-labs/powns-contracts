// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {POWNSStaking} from "./POWNSStaking.sol";

/**
 * @title POWNSGovernor
 * @notice DAO governance for PoWNS protocol
 * @dev Proposal + Voting + Timelock execution
 */
contract POWNSGovernor is Ownable {
    // ============ Enums ============
    
    enum ProposalState {
        Pending,        // Created, in discussion period
        Active,         // Voting in progress
        Defeated,       // Did not pass
        Succeeded,      // Passed, waiting for timelock
        Queued,         // In timelock
        Executed,       // Executed
        Cancelled       // Cancelled by proposer
    }
    
    enum ProposalType {
        Parameter,      // Parameter adjustment
        Upgrade,        // Contract upgrade
        Treasury        // Treasury spending
    }

    // ============ Structs ============
    
    struct Proposal {
        uint256 id;
        address proposer;
        ProposalType proposalType;
        string description;
        bytes[] calldatas;
        address[] targets;
        uint256[] values;
        uint256 startTime;        // Discussion ends, voting starts
        uint256 endTime;          // Voting ends
        uint256 executionTime;    // When timelock ends
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        bool executed;
        bool cancelled;
        mapping(address => bool) hasVoted;
    }

    // ============ Constants ============
    
    /// @notice Discussion period: 3 days
    uint256 public constant DISCUSSION_PERIOD = 3 days;
    
    /// @notice Voting period: 5 days
    uint256 public constant VOTING_PERIOD = 5 days;
    
    /// @notice Timelock delay: 2 days
    uint256 public constant TIMELOCK_DELAY = 2 days;
    
    /// @notice Quorum for parameter changes: 10%
    uint256 public constant QUORUM_PARAMETER = 1000; // basis points
    
    /// @notice Quorum for upgrades: 20%
    uint256 public constant QUORUM_UPGRADE = 2000;
    
    /// @notice Quorum for treasury: 15%
    uint256 public constant QUORUM_TREASURY = 1500;
    
    /// @notice Proposal threshold for parameter: 0.1% of supply
    uint256 public constant THRESHOLD_PARAMETER = 10; // basis points
    
    /// @notice Proposal threshold for upgrade: 1% of supply
    uint256 public constant THRESHOLD_UPGRADE = 100;
    
    /// @notice Proposal threshold for treasury: 0.5% of supply
    uint256 public constant THRESHOLD_TREASURY = 50;
    
    uint256 public constant BASIS_POINTS = 10000;

    // ============ Storage ============
    
    /// @notice Staking contract for voting power
    POWNSStaking public staking;
    
    /// @notice Proposal counter
    uint256 public proposalCount;
    
    /// @notice Proposals by ID
    mapping(uint256 => Proposal) public proposals;
    
    /// @notice Total voting power snapshot at proposal creation
    mapping(uint256 => uint256) public proposalTotalVotingPower;

    // ============ Events ============
    
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        ProposalType proposalType,
        string description
    );
    
    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        uint8 support, // 0 = against, 1 = for, 2 = abstain
        uint256 weight
    );
    
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCancelled(uint256 indexed proposalId);

    // ============ Errors ============
    
    error InsufficientVotingPower();
    error ProposalNotActive();
    error ProposalNotSucceeded();
    error ProposalNotQueued();
    error AlreadyVoted();
    error TimelockNotPassed();
    error ExecutionFailed();
    error NotProposer();
    error InvalidProposalState();

    // ============ Constructor ============
    
    constructor(address _staking) Ownable(msg.sender) {
        staking = POWNSStaking(payable(_staking));
    }

    // ============ Proposal Functions ============
    
    /**
     * @notice Create a new proposal
     */
    function propose(
        ProposalType proposalType,
        string calldata description,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    ) external returns (uint256 proposalId) {
        // Check proposal threshold
        uint256 votingPower = staking.getVotingPower(msg.sender);
        uint256 totalVotingPower = _getTotalVotingPower();
        uint256 threshold = _getThreshold(proposalType, totalVotingPower);
        
        if (votingPower < threshold) revert InsufficientVotingPower();
        
        proposalId = ++proposalCount;
        
        Proposal storage proposal = proposals[proposalId];
        proposal.id = proposalId;
        proposal.proposer = msg.sender;
        proposal.proposalType = proposalType;
        proposal.description = description;
        proposal.targets = targets;
        proposal.values = values;
        proposal.calldatas = calldatas;
        proposal.startTime = block.timestamp + DISCUSSION_PERIOD;
        proposal.endTime = proposal.startTime + VOTING_PERIOD;
        
        proposalTotalVotingPower[proposalId] = totalVotingPower;
        
        emit ProposalCreated(proposalId, msg.sender, proposalType, description);
    }

    /**
     * @notice Cast a vote
     * @param proposalId Proposal ID
     * @param support 0 = against, 1 = for, 2 = abstain
     */
    function castVote(uint256 proposalId, uint8 support) external {
        Proposal storage proposal = proposals[proposalId];
        
        if (getState(proposalId) != ProposalState.Active) revert ProposalNotActive();
        if (proposal.hasVoted[msg.sender]) revert AlreadyVoted();
        
        uint256 weight = staking.getVotingPower(msg.sender);
        
        proposal.hasVoted[msg.sender] = true;
        
        if (support == 0) {
            proposal.againstVotes += weight;
        } else if (support == 1) {
            proposal.forVotes += weight;
        } else {
            proposal.abstainVotes += weight;
        }
        
        emit VoteCast(proposalId, msg.sender, support, weight);
    }

    /**
     * @notice Queue a succeeded proposal for execution
     */
    function queue(uint256 proposalId) external {
        if (getState(proposalId) != ProposalState.Succeeded) revert ProposalNotSucceeded();
        
        Proposal storage proposal = proposals[proposalId];
        proposal.executionTime = block.timestamp + TIMELOCK_DELAY;
    }

    /**
     * @notice Execute a queued proposal
     */
    function execute(uint256 proposalId) external {
        if (getState(proposalId) != ProposalState.Queued) revert ProposalNotQueued();
        
        Proposal storage proposal = proposals[proposalId];
        
        if (block.timestamp < proposal.executionTime) revert TimelockNotPassed();
        
        proposal.executed = true;
        
        for (uint256 i = 0; i < proposal.targets.length; i++) {
            (bool success, ) = proposal.targets[i].call{value: proposal.values[i]}(
                proposal.calldatas[i]
            );
            if (!success) revert ExecutionFailed();
        }
        
        emit ProposalExecuted(proposalId);
    }

    /**
     * @notice Cancel a proposal (only proposer, before execution)
     */
    function cancel(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        
        if (proposal.proposer != msg.sender) revert NotProposer();
        if (proposal.executed) revert InvalidProposalState();
        
        proposal.cancelled = true;
        
        emit ProposalCancelled(proposalId);
    }

    // ============ View Functions ============
    
    function getState(uint256 proposalId) public view returns (ProposalState) {
        Proposal storage proposal = proposals[proposalId];
        
        if (proposal.cancelled) return ProposalState.Cancelled;
        if (proposal.executed) return ProposalState.Executed;
        
        if (block.timestamp < proposal.startTime) {
            return ProposalState.Pending;
        }
        
        if (block.timestamp <= proposal.endTime) {
            return ProposalState.Active;
        }
        
        // Voting ended, check result
        uint256 quorum = _getQuorum(proposal.proposalType, proposalTotalVotingPower[proposalId]);
        uint256 totalVotes = proposal.forVotes + proposal.againstVotes + proposal.abstainVotes;
        
        if (totalVotes < quorum) {
            return ProposalState.Defeated; // Quorum not met
        }
        
        // Check approval threshold
        bool approvalMet;
        if (proposal.proposalType == ProposalType.Upgrade) {
            // 2/3 supermajority
            approvalMet = proposal.forVotes * 3 > (proposal.forVotes + proposal.againstVotes) * 2;
        } else {
            // Simple majority
            approvalMet = proposal.forVotes > proposal.againstVotes;
        }
        
        if (!approvalMet) {
            return ProposalState.Defeated;
        }
        
        if (proposal.executionTime == 0) {
            return ProposalState.Succeeded;
        }
        
        return ProposalState.Queued;
    }

    function getProposalVotes(uint256 proposalId) external view returns (
        uint256 forVotes,
        uint256 againstVotes,
        uint256 abstainVotes
    ) {
        Proposal storage proposal = proposals[proposalId];
        return (proposal.forVotes, proposal.againstVotes, proposal.abstainVotes);
    }

    function hasVoted(uint256 proposalId, address voter) external view returns (bool) {
        return proposals[proposalId].hasVoted[voter];
    }

    // ============ Internal ============
    
    function _getTotalVotingPower() internal view returns (uint256) {
        return staking.totalStaked(); // Simplified, should use snapshot
    }
    
    function _getThreshold(ProposalType proposalType, uint256 total) internal pure returns (uint256) {
        if (proposalType == ProposalType.Parameter) {
            return (total * THRESHOLD_PARAMETER) / BASIS_POINTS;
        } else if (proposalType == ProposalType.Upgrade) {
            return (total * THRESHOLD_UPGRADE) / BASIS_POINTS;
        } else {
            return (total * THRESHOLD_TREASURY) / BASIS_POINTS;
        }
    }
    
    function _getQuorum(ProposalType proposalType, uint256 total) internal pure returns (uint256) {
        if (proposalType == ProposalType.Parameter) {
            return (total * QUORUM_PARAMETER) / BASIS_POINTS;
        } else if (proposalType == ProposalType.Upgrade) {
            return (total * QUORUM_UPGRADE) / BASIS_POINTS;
        } else {
            return (total * QUORUM_TREASURY) / BASIS_POINTS;
        }
    }

    // ============ Receive ETH ============
    
    receive() external payable {}
}
