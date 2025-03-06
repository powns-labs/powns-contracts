// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./interfaces/IPoWNSRegistry.sol";
import "./interfaces/IPoWNSVerifier.sol";
import "./DifficultyManager.sol";
import "./NFTRenderer.sol";

/**
 * @title PoWRegistry
 * @notice Core registry for PoW Name Service (.pow domains)
 * @dev Domains are ERC-721 NFTs with on-chain SVG, scarcity determined by PoW
 */
contract PoWNSRegistry is
    IPoWNSRegistry,
    ERC721Enumerable,
    DifficultyManager,
    Ownable,
    ReentrancyGuard
{
    // ============ Constants ============

    /// @notice Seconds per year
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    /// @notice Maximum registration years
    uint8 public constant MAX_YEARS = 10;

    /// @notice Minimum name length
    uint256 public constant MIN_NAME_LENGTH = 3;

    /// @notice Maximum name length
    uint256 public constant MAX_NAME_LENGTH = 64;

    // ============ Storage ============

    /// @notice Verifier contract
    IPoWNSVerifier public verifier;

    /// @notice Domain data by nameHash
    mapping(bytes32 => Domain) private domains;

    /// @notice Name string by nameHash (for reverse lookup)
    mapping(bytes32 => string) public names;

    /// @notice TokenId by nameHash
    mapping(bytes32 => uint256) public tokenIds;

    /// @notice NameHash by tokenId
    mapping(uint256 => bytes32) public nameHashes;

    /// @notice Deposit amount by nameHash
    mapping(bytes32 => uint256) public deposits;

    /// @notice Next token ID
    uint256 private _nextTokenId;

    /// @notice Minimum deposit per year (in wei)
    uint256 public minDepositPerYear;

    // ============ Constructor ============

    constructor(
        address _verifier,
        uint256 _minDepositPerYear
    ) ERC721("PoW Names", "POW") Ownable(msg.sender) {
        verifier = IPoWNSVerifier(_verifier);
        minDepositPerYear = _minDepositPerYear;
        _nextTokenId = 1;
    }

    // ============ Modifiers ============

    modifier validName(string calldata name) {
        bytes memory b = bytes(name);
        require(b.length >= MIN_NAME_LENGTH, "Name too short");
        require(b.length <= MAX_NAME_LENGTH, "Name too long");
        require(_isValidNameChars(b), "Invalid characters");
        _;
    }

    modifier validYears(uint8 years_) {
        require(years_ >= 1 && years_ <= MAX_YEARS, "Invalid years");
        _;
    }

    // ============ Registration Functions ============

    /**
     * @notice Register a new domain with PoW
     */
    function register(
        string calldata name,
        address owner,
        address miner,
        uint256 nonce,
        uint8 years_
    ) external payable nonReentrant validName(name) validYears(years_) {
        bytes32 nameHash = keccak256(bytes(name));

        // Check availability
        require(_isAvailable(nameHash), "Domain not available");

        // Verify PoW
        uint256 target = getTarget(name);
        (bool valid, ) = verifier.verify(name, owner, miner, nonce, target);
        require(valid, "Invalid PoW");

        // Check deposit
        uint256 requiredDeposit = minDepositPerYear * years_;
        require(msg.value >= requiredDeposit, "Insufficient deposit");

        // Calculate expiration
        uint256 expires = block.timestamp + (SECONDS_PER_YEAR * years_);

        // Store domain
        domains[nameHash] = Domain({
            owner: owner,
            expires: expires,
            registeredAt: block.timestamp,
            state: DomainState.Active
        });

        names[nameHash] = name;
        deposits[nameHash] = msg.value;

        // Mint NFT
        uint256 tokenId = _nextTokenId++;
        tokenIds[nameHash] = tokenId;
        nameHashes[tokenId] = nameHash;
        _safeMint(owner, tokenId);

        // Record for difficulty adjustment
        _recordRegistration();

        // Refund excess
        if (msg.value > requiredDeposit) {
            (bool success, ) = payable(msg.sender).call{
                value: msg.value - requiredDeposit
            }("");
            require(success, "Refund failed");
        }

        emit DomainRegistered(
            name,
            name,
            owner,
            miner,
            expires,
            _calculateDifficultyBits(name)
        );
    }

    /**
     * @notice Renew an existing domain with PoW
     */
    function renew(
        string calldata name,
        uint256 nonce,
        uint8 additionalYears
    ) external payable nonReentrant validYears(additionalYears) {
        bytes32 nameHash = keccak256(bytes(name));
        Domain storage domain = domains[nameHash];

        // Check owner or grace period
        require(
            domain.owner == msg.sender ||
                (domain.state == DomainState.GracePeriod &&
                    domain.owner == msg.sender),
            "Not authorized"
        );

        // Calculate renewal difficulty
        uint256 baseBits = _calculateDifficultyBits(name);
        uint256 multiplier = _getRenewalMultiplier(additionalYears);
        uint256 renewalBits = (baseBits * multiplier) / 100;
        if (renewalBits > MAX_DIFFICULTY_BITS) {
            renewalBits = MAX_DIFFICULTY_BITS;
        }
        uint256 target = _bitsToTarget(renewalBits);

        // Verify PoW
        (bool valid, ) = verifier.verify(
            name,
            domain.owner,
            msg.sender,
            nonce,
            target
        );
        require(valid, "Invalid renewal PoW");

        // Check deposit
        uint256 requiredDeposit = minDepositPerYear * additionalYears;
        require(msg.value >= requiredDeposit, "Insufficient deposit");

        // Extend expiration
        uint256 baseTime = domain.expires > block.timestamp
            ? domain.expires
            : block.timestamp;
        domain.expires = baseTime + (SECONDS_PER_YEAR * additionalYears);
        domain.state = DomainState.Active;

        deposits[nameHash] += msg.value;

        // Record for difficulty adjustment
        _recordRegistration();

        emit DomainRenewed(
            name,
            name,
            domain.owner,
            domain.expires,
            additionalYears
        );
    }

    /**
     * @notice Release a domain and get deposit refund
     */
    function release(string calldata name) external nonReentrant {
        bytes32 nameHash = keccak256(bytes(name));
        Domain storage domain = domains[nameHash];

        require(domain.owner == msg.sender, "Not owner");
        require(domain.state == DomainState.Active, "Not active");

        // Burn NFT
        uint256 tokenId = tokenIds[nameHash];
        _burn(tokenId);

        // Refund deposit
        uint256 refund = deposits[nameHash];
        deposits[nameHash] = 0;

        // Update state
        domain.state = DomainState.Released;
        domain.owner = address(0);

        // Clear mappings
        delete tokenIds[nameHash];
        delete nameHashes[tokenId];

        // Transfer refund
        if (refund > 0) {
            (bool success, ) = payable(msg.sender).call{value: refund}("");
            require(success, "Refund failed");
        }

        emit DomainReleased(name, name, msg.sender, refund);
    }

    // ============ State Management ============

    /**
     * @notice Update domain state based on time
     */
    function updateState(string calldata name) external {
        bytes32 nameHash = keccak256(bytes(name));
        _updateState(nameHash);
    }

    function _updateState(bytes32 nameHash) internal {
        Domain storage domain = domains[nameHash];

        if (domain.state == DomainState.Active) {
            if (block.timestamp > domain.expires) {
                domain.state = DomainState.Expired;
            }
        } else if (domain.state == DomainState.Expired) {
            // After expiration, immediately enter grace period
            domain.state = DomainState.GracePeriod;
        } else if (domain.state == DomainState.GracePeriod) {
            if (block.timestamp > domain.expires + GRACE_PERIOD) {
                domain.state = DomainState.Auction;
                auctionStartTime[nameHash] = block.timestamp;
            }
        }
    }

    // ============ Query Functions ============

    function ownerOf(string calldata name) external view returns (address) {
        bytes32 nameHash = keccak256(bytes(name));
        return domains[nameHash].owner;
    }

    function expiresAt(string calldata name) external view returns (uint256) {
        bytes32 nameHash = keccak256(bytes(name));
        return domains[nameHash].expires;
    }

    function getDomain(
        string calldata name
    ) external view returns (Domain memory) {
        bytes32 nameHash = keccak256(bytes(name));
        return domains[nameHash];
    }

    function getState(
        string calldata name
    ) external view returns (DomainState) {
        bytes32 nameHash = keccak256(bytes(name));
        return _getCurrentState(nameHash);
    }

    function getDifficulty(
        string calldata name
    ) external view returns (uint256) {
        return _calculateDifficultyBits(name);
    }

    function isAvailable(string calldata name) external view returns (bool) {
        bytes32 nameHash = keccak256(bytes(name));
        return _isAvailable(nameHash);
    }

    function verifyPoW(
        string calldata name,
        address owner,
        address miner,
        uint256 nonce
    ) external view returns (bool) {
        uint256 target = getTarget(name);
        (bool valid, ) = verifier.verify(name, owner, miner, nonce, target);
        return valid;
    }

    function computeTarget(
        string calldata name
    ) external view returns (uint256) {
        return getTarget(name);
    }

    // ============ Internal Functions ============

    function _isAvailable(bytes32 nameHash) internal view returns (bool) {
        DomainState state = _getCurrentState(nameHash);
        return
            state == DomainState.Available ||
            state == DomainState.Released ||
            state == DomainState.Auction;
    }

    function _getCurrentState(
        bytes32 nameHash
    ) internal view returns (DomainState) {
        Domain storage domain = domains[nameHash];

        // Never registered
        if (domain.registeredAt == 0) {
            return DomainState.Available;
        }

        // Check time-based transitions
        if (domain.state == DomainState.Active) {
            if (block.timestamp > domain.expires) {
                if (block.timestamp > domain.expires + GRACE_PERIOD) {
                    return DomainState.Auction;
                }
                return DomainState.GracePeriod;
            }
        } else if (domain.state == DomainState.GracePeriod) {
            if (block.timestamp > domain.expires + GRACE_PERIOD) {
                return DomainState.Auction;
            }
        }

        return domain.state;
    }

    function _isValidNameChars(bytes memory name) internal pure returns (bool) {
        for (uint256 i = 0; i < name.length; i++) {
            bytes1 char = name[i];
            // Allow: a-z, 0-9, hyphen (but not at start/end)
            bool isLowercase = (char >= 0x61 && char <= 0x7A);
            bool isDigit = (char >= 0x30 && char <= 0x39);
            bool isHyphen = (char == 0x2D);

            if (!isLowercase && !isDigit && !isHyphen) {
                return false;
            }

            // Hyphen not allowed at start or end
            if (isHyphen && (i == 0 || i == name.length - 1)) {
                return false;
            }
        }
        return true;
    }

    // ============ ERC721 Overrides ============

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override(ERC721Enumerable) returns (address) {
        address from = super._update(to, tokenId, auth);

        // Update domain owner on transfer
        if (from != address(0) && to != address(0)) {
            bytes32 nameHash = nameHashes[tokenId];
            domains[nameHash].owner = to;
            emit DomainTransferred(names[nameHash], from, to);
        }

        return from;
    }

    function _increaseBalance(
        address account,
        uint128 value
    ) internal override(ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @notice Get token URI with on-chain SVG
     */
    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        _requireOwned(tokenId);

        bytes32 nameHash = nameHashes[tokenId];
        Domain storage domain = domains[nameHash];
        string memory name = names[nameHash];

        return
            NFTRenderer.tokenURI(tokenId, name, domain.owner, domain.expires);
    }

    // ============ Admin Functions ============

    function setVerifier(address _verifier) external onlyOwner {
        verifier = IPoWNSVerifier(_verifier);
    }

    function setMinDepositPerYear(uint256 _minDeposit) external onlyOwner {
        minDepositPerYear = _minDeposit;
    }
}
