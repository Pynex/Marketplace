// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Errors} from "./MainContractErrors.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title contract that create new NFR collection.
 * @notice this contract use in MainContract.
 * @dev in the MainContract we use mint function when user buys product(-s).
 */
contract ERC721NewCollection is ERC721, ReentrancyGuard {
    uint256 private tokenCounter;
    string private baseURI;
    address public mainContract;
    address private creator;
    address private platformOwner;

    /**
    * @dev Constructor for the ERC721NewCollection contract.
    * @param _name The name of the NFT collection.
    * @param _symbol The symbol of the NFT collection.
    * @param _collectionURI The base URI for the NFT metadata.
    * @param _creator The address that created the collection.
    * @param _platformOwner the owner mainContract address.
    * @param _mainContract The address of the main contract that can mint NFTs.
    */
    constructor(
        string memory _name,
        string memory _symbol,
        string memory _collectionURI,
        address _creator,
        address _platformOwner,
        address _mainContract
    ) ERC721(_name, _symbol) {
        require(_creator != address(0), "Creator cannot be zero address");
        require(
            _platformOwner != address(0),
            "Marketplace creator cannot be zero address"
        );
        require(
            _mainContract != address(0),
            "Main contract cannot be zero address"
        );

        creator = _creator;
        platformOwner = _platformOwner;
        baseURI = _collectionURI;
        tokenCounter;
        mainContract = _mainContract;
    }

    /// @notice modifier for collection's owner and for main contract owner.
    modifier onlyCreator() {
        require(
            msg.sender == platformOwner || msg.sender == creator,
            "Only creator can call this function"
        );
        _;
    }
    /// @notice modifier for mainContract address.
    modifier onlyMainContract() {
        require(
            msg.sender == mainContract,
            "Only mainContract can call this function"
        );
        _;
    }

    /// @dev mints NFT to the buyer address, when he reedemed a promo code.
    /// @param _to the buyer address to mint the NFT to.
    function mint(address _to) external onlyMainContract nonReentrant {
        uint256 newTokenId = tokenCounter;
        _safeMint(_to, newTokenId);
        tokenCounter++;
    }

    function setApprovalForAll(address operator, bool approved)
        public
        override
        onlyCreator
    {
        super.setApprovalForAll(operator, approved);
    }

    /// @dev returns the base URI for the contract.
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /// @dev returns the URI for a given token ID.
    /// @param tokenId the Id of the token
    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        return string(abi.encodePacked(baseURI, Strings.toString(tokenId)));
    }
}

    /**
    * @title Main contract for managing NFT collections and purchases.
    * @author Pynex.
    * @author ivaaaaaaaaaaaa.
    * @notice This contract handles the creation of new NFT collections,
    *         manages product purchases, and tracks promotional codes.
    */

contract MainContract is Ownable, Errors, ReentrancyGuard {

    //counter for unique collection IDs.
    uint256 public idCounter = 1;
    //amount of market place commission (in %).
    uint256 public immutable commission = 5;
    uint256 private constant MAX_NAME_LENGTH = 64;
    uint256 private constant MAX_SYMBOL_LENGTH = 8;

    /// @notice _id => CollectionInfo (name,symbol and more)
    mapping(uint256 => CollectionInfo) public collections;
    /// @notice _user => promoCode
    //!!!change to mapping (address => mapping(uint (collection id) => bytes8[]))
    mapping(address => mapping (uint => bytes8[])) public uniqPromoForUser;

    /**
    * @dev Structure containing information about an NFT collection.
    * @param name The name of the collection.
    * @param symbol The symbol of the collection.
    * @param collectionOwner The address of the collection owner.
    * @param collectionURI The base URI for the collection's metadata.
    * @param price The price of each NFT in the collection.
    * @param quantityInStock The number of NFTs currently available in the collection.
    * @param collectionAddress The address of the ERC721 contract for the collection.
    * @param id The unique ID of the collection.
    */
    struct CollectionInfo {
        string name;
        string symbol;
        address collectionOwner;
        string collectionURI;
        uint256 price;
        uint256 quantityInStock;
        address collectionAddress;
        uint256 id;
    }

    /**
    * @dev Event emitted when a new NFT collection is created.
    * @param newCollectionAddress The address of the newly created ERC721 contract.
    * @param collectionOwner The address of the collection owner.
    * @param collectionURI The base URI for the collection's metadata.
    * @param collectionName The name of the collection.
    * @param price The price of each NFT in the collection.
    * @param id The unique ID of the collection.
    */
    event collectionCreated(
        address newCollectionAddress,
        address collectionOwner,
        string collectionURI,
        string collectionName,
        uint256 price,
        uint256 id
    );

    /**
    * @dev Event emitted when a product (NFT) is purchased.
    * @param buyer The address of the buyer.
    * @param collectionAddress The address of the ERC721 contract.
    * @param price The price of the purchased NFT.
    * @param cQuantity The quantity of NFTs purchased.
    */
    event productPurchased(
        address indexed buyer,
        address indexed collectionAddress,
        uint256 price,
        uint256 cQuantity
    );

    /**
    * @dev Event emitted when a promotional code is successfully used.
    * @param user The address of the user who used the promo code.
    * @param collectionAddress The address of the ERC721 contract where the promo code was used.
    */
    event promoCodeSuccessfullyUsed(
        address indexed user,
        address indexed collectionAddress
    );

    /**
    * @dev Constructor for the MainContract.
    * @param initialOwner The address of the initial owner of the contract.
    * @param _commission The commission percentage for the platform.
    */
    constructor(address initialOwner, uint256 _commission) Ownable(initialOwner) {
        require(_commission <= 100, "Commission cannot exceed 100%");
        commission = _commission;
    }

    //                                                     ------------------------------------------
    //                                                     -           Main Functionality           -
    //                                                     ------------------------------------------

    /**
    * @dev Allows a user to buy a specified quantity of NFTs from a collection.
    * @param _id The ID of the collection to buy from.
    * @param _quantity The quantity of NFTs to buy.
    */
    function buy(uint256 _id, uint256 _quantity) external payable nonReentrant {
        require(collections[_id].collectionAddress != address(0), incorrectId());

        // Get price and quantity.
        uint256 price = collections[_id].price;
        uint256 cQuantity = collections[_id].quantityInStock;
        require(cQuantity >= _quantity, incorrectQuantity());

        // Calculate total price and commission.
        uint256 totalPrice = price * _quantity;
        require(msg.value >= totalPrice, notEnoughFunds());
        uint256 fundsForSeller = totalPrice - (totalPrice * commission) / 100;
        uint256 amountOfCommission = totalPrice - fundsForSeller;

        // Refund excess funds to the buyer (if any).
        if (msg.value > totalPrice) {
            payable(msg.sender).transfer(msg.value - totalPrice);
        }
        // Update quantity in stock.
        _updateQuantity(_id, cQuantity - _quantity);

        // Generate promo code(-s)
        _generatePromoCode(_quantity, msg.sender, _id);

        // Transfer funds for seller and comission for owner.
        payable(getOwnerByCollectionId(_id)).transfer(fundsForSeller);
        payable(owner()).transfer(amountOfCommission);
        // Emit event.
        address _collectionAddress = getAddressById(_id);
        emit productPurchased(msg.sender, _collectionAddress, price, _quantity);
    }
    
    /**
     * @notice Allows a user to purchase multiple NFTs from different collections in a single transaction.
     * @dev This function handles the purchase of NFTs, calculates the total price including commission,
     *      transfers funds to the sellers, and refunds any excess funds to the buyer(if need).
     * @param _ids An array of collection IDs representing the NFTs to be purchased.
     * @param _quantities An array of quantities for each NFT to be purchased. Must correspond to the `_ids` array.
     */
    function batchBuy (uint256[] calldata _ids, uint256[] calldata _quantities) external payable nonReentrant {
        require(_ids.length == _quantities.length, arraysMisMatch());
        // Limitation of the number of products in a transaction
        require(_ids.length <= 1000);
        // Initialize the total price
        uint totalPrice = 0;
        for(uint i = 0; i < _ids.length; i++) {
            require(collections[_ids[i]].collectionAddress != address(0), incorrectId());
            require(_quantities[i] > 0, incorrectQuantity());
            uint256 cQuantity = collections[_ids[i]].quantityInStock;
            require(cQuantity >= _quantities[i], incorrectQuantity());

            uint price = (collections[_ids[i]].price)  * _quantities[i];
            totalPrice += price;

            // Update the quantity in stock
            _updateQuantity(_ids[i], cQuantity - _quantities[i]);
            // Generate a promo code for the buyer
            _generatePromoCode(_quantities[i], msg.sender, _ids[i]);

            // Transfer of funds to the seller
            payable(getOwnerByCollectionId(_ids[i])).transfer(price - price*commission /100);

            // Emit an event for the product purchased
            emit productPurchased(msg.sender, getAddressById(_ids[i]),  price, _quantities[i]);
        }
        require(msg.value >= totalPrice, notEnoughFunds());
        uint256 fundsForSeller = totalPrice - (totalPrice * commission) / 100;
        uint amountOfCommission = totalPrice - fundsForSeller;
        
        // Refund excess funds to the buyer (if any).
        if (msg.value > totalPrice) {
            payable(msg.sender).transfer(msg.value - totalPrice);
        }

        // Transfer commission to the contract owner
        payable(owner()).transfer(amountOfCommission);
    }

    /**
    * @dev Creates a new NFT collection. All users can use this function.
    * @param _name The name of the collection.
    * @param _symbol The symbol of the collection.
    * @param _collectionURI The base URI for the collection's metadata.
    * @param _price The price of each NFT in the collection.
    * @param _quantityInStock The number of NFTs initially available in the collection.
    */
    function createCollection(
        string calldata _name,
        string calldata _symbol,
        string calldata _collectionURI,
        uint256 _price,
        uint256 _quantityInStock
    ) external payable nonReentrant {
        // Check input parameters.
        require(
            bytes(_name).length > 0 && bytes(_name).length < MAX_NAME_LENGTH,
            incorrectNameLength()
        );
        require(
            bytes(_symbol).length > 0 && bytes(_symbol).length < MAX_SYMBOL_LENGTH,
            incorrectSymbolLength()
        );
        require(bytes(_collectionURI).length > 0, incorrectURI());
        require(_price > 0, incorrectPrice());

        // Deploy a new ERC721NewCollection contract.
        ERC721NewCollection collection = new ERC721NewCollection(
            _name,
            _symbol,
            _collectionURI,
            msg.sender,
            owner(),
            address(this)
        );
        address collectionAddress = address(collection);

        
        require(collectionAddress != address(0), FailedToDeployContract());

        // Save collection info in the collections mapping.
        CollectionInfo memory newCollection = CollectionInfo({
            name: _name,
            symbol: _symbol,
            collectionOwner: msg.sender,
            collectionURI: _collectionURI,
            price: _price,
            quantityInStock: _quantityInStock,
            collectionAddress: collectionAddress,
            id: idCounter
        });
        collections[idCounter] = newCollection;

        // Emit event.
        emit collectionCreated(
            collectionAddress,
            msg.sender,
            _collectionURI,
            _name,
            _price,
            idCounter
        );

        // Increment after emitting the event
        idCounter++;
    }

    /**
    * @dev Allows a user to redeem a promo code and mint an NFT.
    * @param _id The ID of the collection.
    * @param _promoCode The promo code to redeem.
    */
    function reedemCode (uint256 _id, bytes8 _promoCode) public payable {
        require(collections[_id].collectionAddress != address(0), incorrectId());

        // Get collection contract.
        address _collectionAddress = getAddressById(_id);
        ERC721NewCollection collection = ERC721NewCollection(_collectionAddress);

        // Check if mainContract is valid.
        require(
            address(this) == collection.mainContract(),
            incorrectCollectionAddress()
        );
        // Check if promo code is valud.
        require(_isPromoValid(_promoCode, _id) == true, invalidPromoCode());

        // Mint the NFT.
        collection.mint(msg.sender);

        // Delete promo code for user.
        _deletePromoCode(msg.sender, _promoCode, _id);

        // Emit event.
        emit promoCodeSuccessfullyUsed(msg.sender, _collectionAddress);
    }

    //                                                     ------------------------------------------
    //                                                     -           Get  functions               -
    //                                                     ------------------------------------------

    /**
    * @dev Returns the address of the collection contract by its ID.
    * @param _id The ID of the collection.
    * @return The address of the collection contract.
    */
    function getAddressById(uint256 _id) public view returns (address) {
        require(collections[_id].collectionAddress != address(0), collectionNotFound());
        return (collections[_id].collectionAddress);
    }

    /**
    * @dev Returns the price of an NFT in a collection by the collection's ID.
    * @param _id The ID of the collection.
    * @return The price of the NFT.
    */
    function getPrice(uint256 _id) public view returns (uint256) {
        require(collections[_id].collectionAddress != address(0), collectionNotFound());
        return (collections[_id].price);
    }

    /**
    * @dev Returns the quantity of NFTs in stock for a collection by the collection's ID.
    * @param _id The ID of the collection.
    * @return The quantity of NFTs in stock.
    */
    function getQuantity(uint256 _id) public view returns (uint256) {
        require(collections[_id].collectionAddress != address(0), collectionNotFound());
        return (collections[_id].quantityInStock);
    }

    /**
    * @dev Returns a promo code for a user at a specific index. Only callable by the owner.
    * @dev onlyOwner modifier.
    * @param _indexOfPromo The index of the promo code.
    * @param _user The address of the user.
    * @return The promo code.
    */
    function getPromo(uint256 _indexOfPromo, address _user, uint _id)
        public
        view
        onlyOwner
        returns (bytes8)
    {
        require(_user != address(0), incorrectAddress());
        require(collections[_id].collectionAddress != address(0),collectionNotFound());
        require(
            _indexOfPromo < uniqPromoForUser[_user][_id].length,
            incorrectIndex()
        );
        return (uniqPromoForUser[_user][_id][_indexOfPromo]);
    }

    /**
    * @dev Returns the owner of a collection by the collection's ID.
    * @param _id The ID of the collection.
    * @return The address of the collection owner.
    */
    function getOwnerByCollectionId(uint256 _id) public view returns (address) {
        require(collections[_id].collectionAddress != address(0),collectionNotFound());
        return collections[_id].collectionOwner;
    }

    //                                                     ------------------------------------------
    //                                                     -           Service functions            -
    //                                                     ------------------------------------------

     /**
     * @dev Finds the index of a promo code for a user.
     * @dev It is used in the reedemPromoCode function to get the index in the user's mapping and correctly delete the promo code
            after completing the main logic of the function.
     * @param _user The address of the user.
     * @param _promoCode The promo code to find.
     * @return The index of the promo code and a boolean indicating if the promo code was found.    
     */
    function _findIndexByUserAddress(address _user, bytes8 _promoCode, uint _id)
        internal
        view
        returns (uint256, bool)
    {
        require(_user != address(0), incorrectAddress());
        require(collections[_id].collectionAddress != address(0), collectionNotFound());
        for (uint256 i = 0; i < uniqPromoForUser[_user][_id].length; i++) {
            if (uniqPromoForUser[_user][_id][i] == _promoCode)  {
                return (i, true);
            }
        }
        return (0, false);
    }

    /**
     * @dev Deletes a promo code for a user.
     * @param _user The address of the user.
     * @param _promoCode The promo code to delete.
     */
    function _deletePromoCode(address _user, bytes8 _promoCode, uint _id) internal {
        require(_user != address(0), incorrectAddress());
        require(collections[_id].collectionAddress != address(0), collectionNotFound());
        (uint256 _index, bool _status) = _findIndexByUserAddress(
            _user,
            _promoCode,
            _id
        );

        if (!_status) {
            revert promoCodeNotFound();
        }

        uint256 lastIndex = uniqPromoForUser[_user][_id].length - 1;
        if (_index != lastIndex) {
        uniqPromoForUser[_user][_id][_index] = uniqPromoForUser[_user][_id][lastIndex];
        }
        // Pop the last element (effectively deleting the element at _index)
        uniqPromoForUser[_user][_id].pop();
    }

    /**
     * @dev Checks if a promo code is valid for the sender.
     * @param _promoCode The promo code to check.
     * @return True if the promo code is valid, false otherwise.
     */
    function _isPromoValid(bytes8 _promoCode, uint _id) internal view returns (bool) {
        require(collections[_id].collectionAddress != address(0), collectionNotFound());

        for (uint256 i = 0; i < uniqPromoForUser[msg.sender][_id].length; i++) {
            if (uniqPromoForUser[msg.sender][_id][i] == _promoCode) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Generates unique promo codes for a user and saves them.
     * @param _amount The number of promo codes to create (must be greater than 0).
     * @param _user The address of the user receiving the promo codes (must not be the zero address).
     * @notice Uses a combination of block data, transaction data, and a unique counter (nonce) to create each promo code. 
     *         The generated promo codes are stored in the `uniqPromoForUser` mapping.
     */
    function _generatePromoCode(uint _amount, address _user, uint _id) public {
        require(_user != address(0),incorrectAddress());
        require(_amount > 0, incorrectQuantity());
        
        for (uint i = 0; i < _amount ; i++) {
        bytes8 random = bytes8(
            keccak256(abi.encode((blockhash(block.number - i)),block.timestamp,msg.sender, i, tx.origin,
            block.prevrandao )));
            uniqPromoForUser[_user][_id].push(random);
        }
    }

    /**
     * @dev Updates the price of an NFT in a collection.
     * @param _id The ID of the collection.
     * @param _newPrice The new price of the NFT.
     */
    function _updatePrice(uint256 _id, uint256 _newPrice) private {
        collections[_id].price = _newPrice;
    }

    /**
     * @dev Updates the quantity of NFTs in stock for a collection.
     * @param _id The ID of the collection.
     * @param _newQuantity The new quantity of NFTs in stock.
     */
    function _updateQuantity(uint256 _id, uint256 _newQuantity) private {
        collections[_id].quantityInStock = _newQuantity;
    }
}
