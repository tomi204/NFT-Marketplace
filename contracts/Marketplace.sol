//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract MarketPlaceNFT is ReentrancyGuard {
    //state variables

    address payable public immutable feeAccount; // account receives fees
    uint256 public immutable feePercent; //fee percentage
    uint256 public itemCount;

    struct Item {
        uint256 itemId;
        IERC721 nft;
        uint256 tokenId;
        uint256 price;
        address payable seller;
        bool sold;
    }

    address[] public seller;

    mapping(uint256 => Item) public items;

    constructor(uint256 _feePercent) {
        feeAccount = payable(msg.sender);
        feePercent = _feePercent;
    }

    modifier onlyOwner() {
        require(msg.sender == feeAccount);
        _;
    }

    //functions
    ///sell NFT
    function sellNFT(
        IERC721 _nft,
        uint256 _tokenId,
        uint256 _price
    ) external nonReentrant {
        require(_price > 0, "price must be greater than zero");
        itemCount++;

        _nft.transferFrom(msg.sender, address(this), _tokenId);

        items[itemCount] = Item(
            itemCount,
            _nft,
            _tokenId,
            _price,
            payable(msg.sender),
            false
        );
        emit newNFT(itemCount, address(_nft), _tokenId, _price, msg.sender);
    }

    //buy direct
    function buyNFT(uint256 _itemId) external payable nonReentrant {
        uint256 _totalPrice = getTotalPrice(_itemId); //getting total price
        Item storage item = items[_itemId];
        require(_itemId > 0 && _itemId <= itemCount, "item doesnt exist"); //checking item
        require(!item.sold, "item already sold"); /// checking item
        require(
            msg.value >= _totalPrice,
            "not enough ether to cover item price and market fee"
        ); //require anti scam
        feeAccount.transfer(_totalPrice - item.price); //fee for nft marketplace
        item.seller.transfer(item.price); // send value to seller
        item.sold = true; // set sold = true
        item.nft.transferFrom(address(this), msg.sender, item.tokenId); // trasnfer the nft to the buyer
        emit NftPurchased(
            _itemId,
            address(item.nft),
            address(item.seller),
            true,
            msg.sender
        ); //event nft purchased
    }

    function getTotalPrice(uint256 _itemId) public view returns (uint256) {
        return ((items[_itemId].price * (100 + feePercent)) / 100); //calculate total price
    }

    function setSeller(address payable _seller) public onlyOwner {
        seller.push(_seller); //push seller
    }

    ///events
    event newNFT(
        uint256 itemId,
        address indexed nft,
        uint256 tokenId,
        uint256 price,
        address indexed seller
    );
    event NftPurchased(
        uint256 itemId,
        address indexed nft,
        address indexed seller,
        bool sold,
        address indexed buyer
    );

    ///////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////// Auction code
    ///////////////////////////////////////////////////////////////////////////////////////////

    //State of items
    enum State {
        Active,
        Inactive,
        Canceled
    }

    struct itemAuction {
        // struct of itemAuction
        uint256 itemId;
        IERC721 nft;
        uint256 tokenId;
        uint256 startPrice;
        address payable seller;
        State state;
        bool sold;
        uint256 creatorFee;
        address payable highestBidder; // best bidder address
        uint256 highestBid; // best bid amount
    }
    uint256 public itemCountA; ////itemCount

    mapping(uint256 => itemAuction) public itemsAuction; ///mapping de los items
    mapping(address => uint256) public bids; //bids

    //change operator
    function changeOperator(uint256 _itemId, State _newState) public {
        itemAuction storage ItemAuction = itemsAuction[_itemId];
        _itemId = ItemAuction.itemId;
        require(
            msg.sender == ItemAuction.seller,
            "you dont are the owner of the nft"
        );
        ItemAuction.state = _newState;
    }

    ///get total price for auction
    function getTotalPriceAuction(uint256 _itemId)
        public
        view
        returns (uint256)
    {
        return (itemsAuction[_itemId].highestBid / feePercent); //calculate total price
    }

    //start nft auction
    function startAuction(
        IERC721 _nftA,
        uint256 _tokenId,
        uint256 _startPrice,
        uint256 _creatorFee
    ) public {
        require(_startPrice > 0, "price must be greater than zero");
        itemCountA++;
        _nftA.transferFrom(msg.sender, address(this), _tokenId);
        itemsAuction[itemCountA] = itemAuction(
            itemCountA,
            _nftA,
            _tokenId,
            _startPrice,
            payable(msg.sender),
            State.Active,
            false,
            _creatorFee,
            payable(address(0)),
            0
        );
    }

    function placeOffering(uint256 _itemId) public payable {
        itemAuction storage itemA = itemsAuction[_itemId];
        require(State.Active == itemA.state, "error state is inactive");
        require(itemA.sold == false, "error item sold");
        require(msg.value > itemA.startPrice, "error we need more ether");
        require(msg.value > itemA.highestBid, "error you need send more ether");
        if (itemA.highestBidder != msg.sender) {
            //security
            itemA.highestBidder.transfer(itemA.highestBid); //trasnfer money for old best bidder
        }
        itemA.highestBid = msg.value; // value sent
        itemA.highestBidder = payable(msg.sender); //new best bidder address
        emit Bid(itemA.highestBidder, itemA.highestBid); // event new best bidder
    }

    event Bid(address bidderAddress, uint256 bidderOffer); // event with best bidder

    function closeOffering(uint256 _itemId) external payable {
        uint256 _totalPrice = getTotalPriceAuction(_itemId);
        itemAuction storage ItemAuction = itemsAuction[_itemId];
        require(State.Active == ItemAuction.state, "error state is inactive");
        require(
            msg.sender == ItemAuction.seller,
            "you dont are the owner of the nft"
        );
        require(ItemAuction.sold == false, "error nft sold");
        ItemAuction.sold = true;
        ItemAuction.state = State.Inactive;
        feeAccount.transfer(_totalPrice); //fee for nft marketplace
        ItemAuction.seller.transfer(ItemAuction.highestBid - _totalPrice); // send value to seller
        emit End(ItemAuction.highestBidder, ItemAuction.highestBid);
    }

    event End(address Winner, uint256 BestOffer);
}
