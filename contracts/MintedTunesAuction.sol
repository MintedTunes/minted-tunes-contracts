// MintedTunes Auction Contract 
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

interface IMintedTunesNFT {
	function safeTransferFrom(address from, address to, uint256 tokenId) external;    
    function creatorOf(uint256 _tokenId) external view returns (address);
	function royalties(uint256 _tokenId) external view returns (uint256);        
}

contract MintedTunesAuction is Ownable, ERC721Holder {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 constant public PERCENTS_DIVIDER = 1000;
    uint256 constant public MIN_BID_INCREMENT_PERCENT = 50; // 5%
	uint256 public feePercent = 25;	 // 2.5%
	address public feeAddress;
    
    // Bid struct to hold bidder and amount
    struct Bid {
        address from;
        uint256 bidPrice;
    }

    // Auction struct which holds all the required info
    struct Auction {
        uint256 auctionId;
        address collectionId;
        uint256 tokenId;
        uint256 startTime;
        uint256 endTime;
        uint256 startPrice;
        address creator;
        address owner;
        bool active;       
    }

    // Array with all auctions
    Auction[] public auctions;
    
    // Mapping from auction index to user bids
    mapping (uint256 => Bid[]) public auctionBids;
    
    // Mapping from owner to a list of owned auctions
    mapping (address => uint256[]) public ownedAuctions;
    
    event BidSuccess(address _from, uint256 _auctionId, uint256 _amount, uint256 _bidIndex);

    // AuctionCreated is fired when an auction is created
    event AuctionCreated(Auction auction);

    // AuctionCanceled is fired when an auction is canceled
    event AuctionCanceled(uint _auctionId);

    // AuctionFinalized is fired when an auction is finalized
    event AuctionFinalized(address buyer, Auction auction, uint256 price);

    constructor (uint256 _feePercent, address _feeAddress) {		
		feePercent = _feePercent;	
		feeAddress = _feeAddress;
	}   
    
    function setFee(uint256 _feePercent, 
		address _feeAddress) external onlyOwner {		
        feePercent = _feePercent;
		feeAddress = _feeAddress;		
    }

    /*
     * @dev Creates an auction with the given informatin
     * @param _tokenRepositoryAddress address of the TokenRepository contract
     * @param _tokenId uint256 of the deed registered in DeedRepository
     * @param _startPrice uint256 starting price of the auction
     * @return bool whether the auction is created
     */
    function createAuction(address _collectionId, uint256 _tokenId, uint256 _startPrice, uint256 _startTime, uint256 _endTime) 
        onlyTokenOwner(_collectionId, _tokenId) public 
    {   
        require(block.timestamp < _endTime, "end timestamp have to be bigger than current time");
        
        IMintedTunesNFT nft = IMintedTunesNFT(_collectionId); 

        uint256 auctionId = auctions.length;
        Auction memory newAuction;
        newAuction.auctionId = auctionId;
        newAuction.collectionId = _collectionId;
        newAuction.tokenId = _tokenId;
        newAuction.startPrice = _startPrice;
        newAuction.startTime = _startTime;
        newAuction.endTime = _endTime;
        newAuction.owner = msg.sender;
        newAuction.creator = nft.creatorOf(_tokenId);
        newAuction.active = true;
        
        auctions.push(newAuction);        
        ownedAuctions[msg.sender].push(auctionId);
        
        nft.safeTransferFrom(msg.sender, address(this), _tokenId);        
        emit AuctionCreated(newAuction);       
    }
    
    /**
     * @dev Finalized an ended auction
     * @dev The auction should be ended, and there should be at least one bid
     * @dev On success Deed is transfered to bidder and auction owner gets the amount
     * @param _auctionId uint256 ID of the created auction
     */
    function finalizeAuction(uint256 _auctionId) public {
        Auction memory myAuction = auctions[_auctionId];
        uint256 bidsLength = auctionBids[_auctionId].length;
        require(msg.sender == myAuction.owner || msg.sender == owner(), "only auction owner can finalize");
        
        // if there are no bids cancel
        if(bidsLength == 0) {
            IMintedTunesNFT(myAuction.collectionId).safeTransferFrom(address(this), myAuction.owner, myAuction.tokenId);
            auctions[_auctionId].active = false;           
            emit AuctionCanceled(_auctionId);
        }else{
            // 2. the money goes to the auction owner
            Bid memory lastBid = auctionBids[_auctionId][bidsLength - 1];

            address _creator = IMintedTunesNFT(myAuction.collectionId).creatorOf(myAuction.tokenId);
            uint256 royalty = IMintedTunesNFT(myAuction.collectionId).royalties(myAuction.tokenId);

            // % commission cut
            uint256 _adminValue = lastBid.bidPrice.mul(feePercent).div(PERCENTS_DIVIDER);
            uint256 _creatorValue = lastBid.bidPrice.mul(royalty).div(PERCENTS_DIVIDER);
            uint256 _sellerValue = lastBid.bidPrice.sub(_adminValue).sub(_creatorValue);

            if(_adminValue > 0){
                payable(feeAddress).transfer(_adminValue);
            }
            if(_creatorValue > 0){
                payable(_creator).transfer(_creatorValue);
            }
            payable(myAuction.owner).transfer(_sellerValue);           
            
            // approve and transfer from this contract to the bid winner 
            IMintedTunesNFT(myAuction.collectionId).safeTransferFrom(address(this), lastBid.from, myAuction.tokenId);		
            auctions[_auctionId].active = false;

            emit AuctionFinalized(lastBid.from, myAuction, lastBid.bidPrice);
        }
    }
    
    /**
     * @dev Bidder sends bid on an auction
     * @dev Auction should be active and not ended
     * @dev Refund previous bidder if a new bid is valid and placed.
     * @param _auctionId uint256 ID of the created auction
     */
    function bidOnAuction(uint256 _auctionId, uint256 amount) external payable {
        require(_auctionId <= auctions.length && auctions[_auctionId].auctionId == _auctionId, "Could not find item");
        
        // owner can't bid on their auctions
        Auction memory myAuction = auctions[_auctionId];
        require(myAuction.owner != msg.sender, "owner can not bid");
        require(myAuction.active, "not exist");

        // if auction is expired
        require(block.timestamp < myAuction.endTime, "auction is over");
        require(block.timestamp >= myAuction.startTime, "auction is not started");

        uint256 bidsLength = auctionBids[_auctionId].length;
        uint256 tempAmount = myAuction.startPrice;
        Bid memory lastBid;

        // there are previous bids
        if( bidsLength > 0 ) {
            lastBid = auctionBids[_auctionId][bidsLength - 1];
            tempAmount = lastBid.bidPrice.mul(PERCENTS_DIVIDER + MIN_BID_INCREMENT_PERCENT).div(PERCENTS_DIVIDER);
        }
        

        // check if amount is greater than previous amount  
        require(amount >= tempAmount, "too small amount");
        require(msg.value >= amount, "too small balance");

        // refund the last bidder
        if( bidsLength > 0 ) {
            payable(lastBid.from).transfer(lastBid.bidPrice);            
        }  

        // insert bid 
        Bid memory newBid;
        newBid.from = msg.sender;
        newBid.bidPrice = amount;
        auctionBids[_auctionId].push(newBid);
        emit BidSuccess(msg.sender, _auctionId, newBid.bidPrice, bidsLength);
    }


    /**
     * @dev Gets the length of auctions
     * @return uint256 representing the auction count
     */
    function getAuctionsLength() public view returns(uint) {
        return auctions.length;
    }
    
    /**
     * @dev Gets the bid counts of a given auction
     * @param _auctionId uint256 ID of the auction
     */
    function getBidsAmount(uint256 _auctionId) public view returns(uint) {
        return auctionBids[_auctionId].length;
    } 
    
    /**
     * @dev Gets an array of owned auctions
     * @param _owner address of the auction owner
     */
    function getOwnedAuctions(address _owner) public view returns(uint[] memory) {
        uint[] memory ownedAllAuctions = ownedAuctions[_owner];
        return ownedAllAuctions;
    }
    
    /**
     * @dev Gets an array of owned auctions
     * @param _auctionId uint256 of the auction owner
     * @return amount uint256, address of last bidder
     */
    function getCurrentBids(uint256 _auctionId) public view returns(uint256, address) {
        uint256 bidsLength = auctionBids[_auctionId].length;
        // if there are bids refund the last bid
        if (bidsLength >= 0) {
            Bid memory lastBid = auctionBids[_auctionId][bidsLength - 1];
            return (lastBid.bidPrice, lastBid.from);
        }    
        return (0, address(0));
    }
    
    /**
     * @dev Gets the total number of auctions owned by an address
     * @param _owner address of the owner
     * @return uint256 total number of auctions
     */
    function getAuctionsAmount(address _owner) public view returns(uint) {
        return ownedAuctions[_owner].length;
    }

    modifier onlyAuctionOwner(uint256 _auctionId) {
        require(auctions[_auctionId].owner == msg.sender);
        _;
    }

    modifier onlyTokenOwner(address _collectionId, uint256 _tokenId) {
        address tokenOwner = IERC721(_collectionId).ownerOf(_tokenId);
        require(tokenOwner == msg.sender);
        _;
    }
}