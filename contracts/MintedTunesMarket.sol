// MintedTunes Market contract
// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import "./MintedTunesNFT.sol";

interface IMintedTunesNFT {
	function initialize(string memory _name, string memory _uri, address creator, address _feeAddress, bool bPublic) external;	
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
    function creatorOf(uint256 _tokenId) external view returns (address);
	function royalties(uint256 _tokenId) external view returns (uint256);	
}

contract MintedTunesMarket is Ownable, ERC721Holder {
    using SafeMath for uint256;
	using EnumerableSet for EnumerableSet.AddressSet;

	uint256 constant public PERCENTS_DIVIDER = 1000;

	uint256 public feePercent = 25;	// 2.5%
	address public feeAddress; 

    /* Pairs to swap NFT _id => price */
	struct Pair {
		uint256 pair_id;
		address collection;
		uint256 token_id;
		address creator;
		address owner;
		uint256 price;
        uint256 creatorFee;
        bool bValid;		
	}

	address[] public collections;
	// collection address => creator address

	// token id => Pair mapping
    mapping(uint256 => Pair) public pairs;
	uint256 public currentPairId;
    
	uint256 public totalEarning; /* Total MintedTunes Token */
	uint256 public totalSwapped; /* Total swap count */

	/** Events */
    event CollectionCreated(address collection_address, address owner, string name, string uri, bool isPublic);
    event ItemListed(uint256 id, address collection, uint256 token_id, uint256 price, address creator, address owner, uint256 creatorFee);
	event ItemDelisted(uint256 id);
    event Swapped(address buyer, Pair pair);

	constructor (uint256 _feePercent, 
		address _feeAddress) {		
		feePercent = _feePercent;	
		feeAddress = _feeAddress;
	}
	
	function setFee(uint256 _feePercent, 
		address _feeAddress) external onlyOwner {		
        feePercent = _feePercent;
		feeAddress = _feeAddress;		
    }


	function createCollection(string memory _name, string memory _uri, bool bPublic) public returns(address collection) {
		if(bPublic){
			require(owner() == msg.sender, "Only owner can create public collection");	
		}
		bytes memory bytecode = type(MintedTunesNFT).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(_uri, _name, block.timestamp));
        assembly {
            collection := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IMintedTunesNFT(collection).initialize(_name, _uri, msg.sender, feeAddress, bPublic);
		collections.push(collection);
		
		emit CollectionCreated(collection, msg.sender, _name, _uri, bPublic);
	}
	

    function list(address _collection, uint256 _token_id, uint256 _price) OnlyItemOwner(_collection,_token_id) public {
		require(_price > 0, "invalid price");		

		IMintedTunesNFT nft = IMintedTunesNFT(_collection);        
        nft.safeTransferFrom(msg.sender, address(this), _token_id);

		currentPairId = currentPairId.add(1);

		pairs[currentPairId].pair_id = currentPairId;
		pairs[currentPairId].collection = _collection;
		pairs[currentPairId].token_id = _token_id;
		pairs[currentPairId].creator = nft.creatorOf(_token_id);
        pairs[currentPairId].creatorFee = nft.royalties(_token_id);
		pairs[currentPairId].owner = msg.sender;		
		pairs[currentPairId].price = _price;	
        pairs[currentPairId].bValid = true;	

        emit ItemListed(currentPairId, 
			_collection,
			_token_id, 
			_price, 
			pairs[currentPairId].creator,
			msg.sender,
			pairs[currentPairId].creatorFee
		);
    }

    function delist(uint256 _id) external {        
        require(pairs[_id].bValid, "not exist");

        require(msg.sender == pairs[_id].owner || msg.sender == owner(), "Error, you are not the owner");        
        IMintedTunesNFT(pairs[_id].collection).safeTransferFrom(address(this), pairs[_id].owner, pairs[_id].token_id);        
        pairs[_id].bValid = false;
        emit ItemDelisted(_id);        
    }


    function buy(uint256 _id) external payable{
		require(_id <= currentPairId && pairs[_id].pair_id == _id, "Could not find item");

        require(pairs[_id].bValid, "invalid Pair id");
		require(pairs[_id].owner != msg.sender, "owner can not buy");

		Pair memory pair = pairs[_id];
		uint256 totalAmount = pair.price;

		require(msg.value >= totalAmount, "insufficient balance");

		// transfer Coin to feeAddress
		if (feePercent > 0){
			payable(feeAddress).transfer(totalAmount.mul(feePercent).div(PERCENTS_DIVIDER));
		}

		// transfer Coin to creator
		if (pair.creatorFee > 0){
			payable(pair.creator).transfer(totalAmount.mul(pair.creatorFee).div(PERCENTS_DIVIDER));
		}
		
		// transfer Coin to owner
		uint256 ownerPercent = PERCENTS_DIVIDER.sub(feePercent).sub(pair.creatorFee);
		if (pair.creatorFee > 0){
			payable(pair.owner).transfer(totalAmount.mul(ownerPercent).div(PERCENTS_DIVIDER));
		}		

		// transfer NFT token to buyer
		IMintedTunesNFT(pairs[_id].collection).safeTransferFrom(address(this), msg.sender, pair.token_id);
		
		pairs[_id].bValid = false;

		totalEarning = totalEarning.add(totalAmount);
		totalSwapped = totalSwapped.add(1);

        emit Swapped(msg.sender, pair);		
    }

	modifier OnlyItemOwner(address tokenAddress, uint256 tokenId){
        IMintedTunesNFT tokenContract = IMintedTunesNFT(tokenAddress);
        require(tokenContract.ownerOf(tokenId) == msg.sender);
        _;
    }

}