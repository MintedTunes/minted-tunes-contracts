// MintedTunes NFT token
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract MintedTunesNFT is ERC721 {
    using SafeMath for uint256;

    uint256 constant public PERCENTS_DIVIDER = 1000;
	uint256 constant public FEE_MAX_PERCENT = 200; // 20 %
    uint256 constant public FEE_MIN_PERCENT = 50; // 5 %
    uint256 constant private FEE_MINT = 1000000000000000; // 0.001 ETH
    address public feeAddress;

    string public collection_name;
    string public collection_uri;
    bool public isPublic;
    address public factory;
    address public owner;

    struct Item {
        uint256 id;
        address creator;
        string uri;
        uint256 royalty;
    }
    uint256 public currentID;    
    mapping (uint256 => Item) public Items;


    event CollectionUriUpdated(string collection_uri);    
    event CollectionNameUpdated(string collection_name);
    event TokenUriUpdated(uint256 id, string uri);

    event ItemCreated(uint256 id, address creator, string uri, uint256 royalty);

    constructor() ERC721("MintedTunes","MT") {
        factory = msg.sender;
    }

    /**
		Initialize from Swap contract
	 */
    function initialize(
        string memory _name,
        string memory _uri,
        address creator,
        address _feeAddress,
        bool bPublic
    ) external {
        require(msg.sender == factory, "Only for factory");
        collection_uri = _uri;
        collection_name = _name;
        owner = creator;
        feeAddress = _feeAddress;
        isPublic = bPublic;        
    }

    function setFeeAddress(address _feeAddress) public {
        require(msg.sender == feeAddress, "Admin can only change feeAddress");
        feeAddress = _feeAddress;
    }
    
    /**
		Change & Get Collection Information
	 */
    function setCollectionURI(string memory newURI) public onlyOwner {
        collection_uri = newURI;
        emit CollectionUriUpdated(newURI);
    }

    function setName(string memory newname) public onlyOwner {
        collection_name = newname;
        emit CollectionNameUpdated(newname);
    }

    function transferOwner(address _newOwner) public onlyOwner {
        owner = _newOwner;        
    }

    function getCollectionURI() external view returns (string memory) {
        return collection_uri;
    }
    function getCollectionName() external view returns (string memory) {
        return collection_name;
    }


    /**
		Change & Get Item Information
	 */
    function addItem(string memory _tokenURI, uint256 royalty) public payable returns (uint256){
        require(owner == msg.sender || isPublic, "Only minter can add item");

        require(royalty <= FEE_MAX_PERCENT, "too big royalties");
        require(royalty >= FEE_MIN_PERCENT, "too small royalties");
        require(msg.value >= FEE_MINT, "too small amount");
        payable(feeAddress).transfer(FEE_MINT);
        currentID = currentID.add(1);        
        _safeMint(msg.sender, currentID);
        Items[currentID] = Item(currentID, msg.sender, _tokenURI, royalty);
        emit ItemCreated(currentID, msg.sender, _tokenURI, royalty);
        return currentID;
    }

    function setTokenURI(uint256 _tokenId, string memory _newURI)
        public
        creatorOnly(_tokenId)
    {
        Items[_tokenId].uri = _newURI;
        emit TokenUriUpdated( _tokenId, _newURI);
    }



    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        return Items[tokenId].uri;
    }    

    function creatorOf(uint256 _tokenId) public view returns (address) {
        return Items[_tokenId].creator;
    }

    function royalties(uint256 _tokenId) public view returns (uint256) {
        return Items[_tokenId].royalty;
	}




    modifier onlyOwner() {
        require(owner == _msgSender(), "caller is not the owner");
        _;
    }
    /**
     * @dev Require _msgSender() to be the creator of the token id
     */
    modifier creatorOnly(uint256 _id) {
        require(
            Items[_id].creator == _msgSender(),
            "ERC721Tradable#creatorOnly: ONLY_CREATOR_ALLOWED"
        );
        _;
    }
}
