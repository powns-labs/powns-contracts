// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Marketplace
 * @notice Trading marketplace for PoWNS domains
 * @dev Supports fixed price, offers, and auctions
 */
contract Marketplace is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ Enums ============
    
    enum ListingType {
        FixedPrice,
        Auction
    }

    // ============ Structs ============
    
    struct Listing {
        address seller;
        uint256 tokenId;
        uint256 price;           // Fixed price or starting price
        address paymentToken;    // address(0) = ETH
        ListingType listingType;
        uint256 endTime;         // For auctions
        address highestBidder;   // For auctions
        uint256 highestBid;      // For auctions
        bool active;
    }
    
    struct Offer {
        address buyer;
        uint256 tokenId;
        uint256 amount;
        address paymentToken;
        uint256 expiresAt;
        bool active;
    }

    // ============ Constants ============
    
    /// @notice Trading fee: 2.5%
    uint256 public constant TRADING_FEE_BPS = 250;
    uint256 public constant BASIS_POINTS = 10000;

    // ============ Storage ============
    
    /// @notice Registry contract (NFT)
    IERC721 public registry;
    
    /// @notice Fee recipient
    address public feeRecipient;
    
    /// @notice Listings by tokenId
    mapping(uint256 => Listing) public listings;
    
    /// @notice Offers by offerId
    mapping(bytes32 => Offer) public offers;
    
    /// @notice User offers
    mapping(address => bytes32[]) public userOffers;
    
    /// @notice Active listing count
    uint256 public activeListingCount;
    
    /// @notice Offer counter
    uint256 private _offerCounter;

    // ============ Events ============
    
    event Listed(uint256 indexed tokenId, address indexed seller, uint256 price, ListingType listingType);
    event Unlisted(uint256 indexed tokenId, address indexed seller);
    event Sold(uint256 indexed tokenId, address indexed seller, address indexed buyer, uint256 price);
    event BidPlaced(uint256 indexed tokenId, address indexed bidder, uint256 amount);
    event OfferMade(bytes32 indexed offerId, uint256 indexed tokenId, address indexed buyer, uint256 amount);
    event OfferAccepted(bytes32 indexed offerId, uint256 indexed tokenId, address seller, address buyer);
    event OfferCancelled(bytes32 indexed offerId);

    // ============ Errors ============
    
    error NotOwner();
    error AlreadyListed();
    error NotListed();
    error InvalidPrice();
    error InsufficientPayment();
    error AuctionNotEnded();
    error AuctionEnded();
    error BidTooLow();
    error OfferExpired();
    error OfferNotFound();
    error NotOfferBuyer();
    error TransferFailed();

    // ============ Constructor ============
    
    constructor(address _registry, address _feeRecipient) Ownable(msg.sender) {
        registry = IERC721(_registry);
        feeRecipient = _feeRecipient;
    }

    // ============ Listing Functions ============
    
    /**
     * @notice List a domain for fixed price sale
     */
    function listFixedPrice(
        uint256 tokenId,
        uint256 price,
        address paymentToken
    ) external {
        if (registry.ownerOf(tokenId) != msg.sender) revert NotOwner();
        if (listings[tokenId].active) revert AlreadyListed();
        if (price == 0) revert InvalidPrice();
        
        // Transfer NFT to marketplace
        registry.transferFrom(msg.sender, address(this), tokenId);
        
        listings[tokenId] = Listing({
            seller: msg.sender,
            tokenId: tokenId,
            price: price,
            paymentToken: paymentToken,
            listingType: ListingType.FixedPrice,
            endTime: 0,
            highestBidder: address(0),
            highestBid: 0,
            active: true
        });
        
        activeListingCount++;
        
        emit Listed(tokenId, msg.sender, price, ListingType.FixedPrice);
    }

    /**
     * @notice List a domain for auction
     */
    function listAuction(
        uint256 tokenId,
        uint256 startingPrice,
        uint256 duration
    ) external {
        if (registry.ownerOf(tokenId) != msg.sender) revert NotOwner();
        if (listings[tokenId].active) revert AlreadyListed();
        if (startingPrice == 0) revert InvalidPrice();
        
        registry.transferFrom(msg.sender, address(this), tokenId);
        
        listings[tokenId] = Listing({
            seller: msg.sender,
            tokenId: tokenId,
            price: startingPrice,
            paymentToken: address(0), // ETH only for auctions
            listingType: ListingType.Auction,
            endTime: block.timestamp + duration,
            highestBidder: address(0),
            highestBid: 0,
            active: true
        });
        
        activeListingCount++;
        
        emit Listed(tokenId, msg.sender, startingPrice, ListingType.Auction);
    }

    /**
     * @notice Cancel a listing
     */
    function unlist(uint256 tokenId) external {
        Listing storage listing = listings[tokenId];
        if (!listing.active) revert NotListed();
        if (listing.seller != msg.sender) revert NotOwner();
        
        // For auctions, can only cancel if no bids
        if (listing.listingType == ListingType.Auction && listing.highestBidder != address(0)) {
            revert BidTooLow(); // Cannot cancel auction with bids
        }
        
        listing.active = false;
        activeListingCount--;
        
        // Return NFT
        registry.transferFrom(address(this), msg.sender, tokenId);
        
        emit Unlisted(tokenId, msg.sender);
    }

    // ============ Buying Functions ============
    
    /**
     * @notice Buy a fixed-price listing
     */
    function buy(uint256 tokenId) external payable nonReentrant {
        Listing storage listing = listings[tokenId];
        if (!listing.active) revert NotListed();
        if (listing.listingType != ListingType.FixedPrice) revert NotListed();
        
        uint256 price = listing.price;
        address seller = listing.seller;
        
        // Handle payment
        if (listing.paymentToken == address(0)) {
            if (msg.value < price) revert InsufficientPayment();
        } else {
            IERC20(listing.paymentToken).safeTransferFrom(msg.sender, address(this), price);
        }
        
        // Close listing
        listing.active = false;
        activeListingCount--;
        
        // Calculate fee
        uint256 fee = (price * TRADING_FEE_BPS) / BASIS_POINTS;
        uint256 sellerAmount = price - fee;
        
        // Transfer payments
        if (listing.paymentToken == address(0)) {
            (bool success1, ) = seller.call{value: sellerAmount}("");
            (bool success2, ) = feeRecipient.call{value: fee}("");
            if (!success1 || !success2) revert TransferFailed();
            
            // Refund excess
            if (msg.value > price) {
                (bool success3, ) = msg.sender.call{value: msg.value - price}("");
                if (!success3) revert TransferFailed();
            }
        } else {
            IERC20(listing.paymentToken).safeTransfer(seller, sellerAmount);
            IERC20(listing.paymentToken).safeTransfer(feeRecipient, fee);
        }
        
        // Transfer NFT
        registry.transferFrom(address(this), msg.sender, tokenId);
        
        emit Sold(tokenId, seller, msg.sender, price);
    }

    /**
     * @notice Place bid on auction
     */
    function bid(uint256 tokenId) external payable nonReentrant {
        Listing storage listing = listings[tokenId];
        if (!listing.active) revert NotListed();
        if (listing.listingType != ListingType.Auction) revert NotListed();
        if (block.timestamp >= listing.endTime) revert AuctionEnded();
        
        uint256 minBid = listing.highestBid > 0 
            ? listing.highestBid + (listing.highestBid / 10) // 10% increment
            : listing.price;
        
        if (msg.value < minBid) revert BidTooLow();
        
        // Refund previous bidder
        address previousBidder = listing.highestBidder;
        uint256 previousBid = listing.highestBid;
        
        // Update bid
        listing.highestBidder = msg.sender;
        listing.highestBid = msg.value;
        
        // Refund previous
        if (previousBidder != address(0)) {
            (bool success, ) = previousBidder.call{value: previousBid}("");
            if (!success) revert TransferFailed();
        }
        
        emit BidPlaced(tokenId, msg.sender, msg.value);
    }

    /**
     * @notice Finalize auction after end time
     */
    function finalizeAuction(uint256 tokenId) external nonReentrant {
        Listing storage listing = listings[tokenId];
        if (!listing.active) revert NotListed();
        if (listing.listingType != ListingType.Auction) revert NotListed();
        if (block.timestamp < listing.endTime) revert AuctionNotEnded();
        
        listing.active = false;
        activeListingCount--;
        
        if (listing.highestBidder == address(0)) {
            // No bids, return to seller
            registry.transferFrom(address(this), listing.seller, tokenId);
            emit Unlisted(tokenId, listing.seller);
        } else {
            // Distribute payment
            uint256 price = listing.highestBid;
            uint256 fee = (price * TRADING_FEE_BPS) / BASIS_POINTS;
            uint256 sellerAmount = price - fee;
            
            (bool success1, ) = listing.seller.call{value: sellerAmount}("");
            (bool success2, ) = feeRecipient.call{value: fee}("");
            if (!success1 || !success2) revert TransferFailed();
            
            // Transfer NFT
            registry.transferFrom(address(this), listing.highestBidder, tokenId);
            
            emit Sold(tokenId, listing.seller, listing.highestBidder, price);
        }
    }

    // ============ Offer Functions ============
    
    /**
     * @notice Make an offer on any domain
     */
    function makeOffer(
        uint256 tokenId,
        uint256 expiresAt
    ) external payable returns (bytes32 offerId) {
        if (msg.value == 0) revert InvalidPrice();
        
        offerId = keccak256(abi.encodePacked(msg.sender, tokenId, block.timestamp, _offerCounter++));
        
        offers[offerId] = Offer({
            buyer: msg.sender,
            tokenId: tokenId,
            amount: msg.value,
            paymentToken: address(0),
            expiresAt: expiresAt,
            active: true
        });
        
        userOffers[msg.sender].push(offerId);
        
        emit OfferMade(offerId, tokenId, msg.sender, msg.value);
    }

    /**
     * @notice Accept an offer
     */
    function acceptOffer(bytes32 offerId) external nonReentrant {
        Offer storage offer = offers[offerId];
        if (!offer.active) revert OfferNotFound();
        if (block.timestamp > offer.expiresAt) revert OfferExpired();
        if (registry.ownerOf(offer.tokenId) != msg.sender) revert NotOwner();
        
        offer.active = false;
        
        uint256 price = offer.amount;
        uint256 fee = (price * TRADING_FEE_BPS) / BASIS_POINTS;
        uint256 sellerAmount = price - fee;
        
        // Transfer payments
        (bool success1, ) = msg.sender.call{value: sellerAmount}("");
        (bool success2, ) = feeRecipient.call{value: fee}("");
        if (!success1 || !success2) revert TransferFailed();
        
        // Transfer NFT
        registry.transferFrom(msg.sender, offer.buyer, offer.tokenId);
        
        emit OfferAccepted(offerId, offer.tokenId, msg.sender, offer.buyer);
    }

    /**
     * @notice Cancel an offer
     */
    function cancelOffer(bytes32 offerId) external nonReentrant {
        Offer storage offer = offers[offerId];
        if (!offer.active) revert OfferNotFound();
        if (offer.buyer != msg.sender) revert NotOfferBuyer();
        
        offer.active = false;
        
        // Refund
        (bool success, ) = msg.sender.call{value: offer.amount}("");
        if (!success) revert TransferFailed();
        
        emit OfferCancelled(offerId);
    }

    // ============ View Functions ============
    
    function getListing(uint256 tokenId) external view returns (Listing memory) {
        return listings[tokenId];
    }
    
    function getOffer(bytes32 offerId) external view returns (Offer memory) {
        return offers[offerId];
    }

    // ============ Admin ============
    
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        feeRecipient = _feeRecipient;
    }
}
