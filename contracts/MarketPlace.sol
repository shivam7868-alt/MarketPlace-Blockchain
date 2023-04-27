// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import "./IERC1155.sol";
import "./IERC721.sol";
import "./IERC20.sol";

contract MarketPlace {
    address private marketPlaceOwner;
    //NFT Address=> tokenId => .
    mapping(address => mapping(uint256 => info)) private TokensOnSale;
    uint8 public feeCharge = 55;
    uint8 public decimals = 2;
    struct info { 
        uint256 price;
        uint256 numberOfTokens; 
        address tokenOwner;
        address exchangeAcceptedAddress;
    }
    address[] buyersToken;
    event SellToken(
        address indexed _seller,
        uint256 indexed _id,
        address indexed _tokenAddress,
        uint256 _numberOfTokens
    );
    event BuyToken(
        address indexed buyer,
        address indexed _tokenAddress,
        uint256 indexed _tokenId
    );
    IERC1155 erc1155;
    IERC721 erc721;

    modifier notZeroAddress(address _tokenAddress) {
        require(
            _tokenAddress != address(0),
            "tokenAddres you provided can not be zero"
        );
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == marketPlaceOwner, "not authorized to withdraw");
        _;
    }

    modifier onSale(address _tokenAddress, uint256 _id) {
        require(
            TokensOnSale[_tokenAddress][_id].tokenOwner != address(0),
            "token id is not on sale"
        );
        _;
    }

    constructor() {
        marketPlaceOwner = msg.sender;
    }

    receive() external payable {}

    function sellERC721(
        address _NFTAddress,
        uint256 _id,
        uint256 _price,
        address _tokensAcceptedAddress
    ) external notZeroAddress(_NFTAddress) {
        erc721 = IERC721(_NFTAddress);
        require(
            erc721.ownerOf(_id) == msg.sender,
            "you do not own this token id"
        );
        require(
            erc721.getApproved(_id) == address(this) ||
                erc721.isApprovedForAll(msg.sender, address(this)),
            "please approve the contract"
        );
        TokensOnSale[_NFTAddress][_id] = info(
            _price,
            1,
            msg.sender,
            _tokensAcceptedAddress
        );
        emit SellToken(msg.sender, _id, _NFTAddress, 1);
    }

    function sellERC1155(
        address _semiNFTAddress,
        uint256 _id,
        uint256 _price,
        uint256 _numberOfTokens,
        address _tokensAcceptedAddress
    ) external notZeroAddress(_semiNFTAddress) {
        erc1155 = IERC1155(_semiNFTAddress);
        require(
            _numberOfTokens > 0,
            "please enter number of tokens greater than 0"
        );
        require(
            erc1155.balanceOf(msg.sender, _id) >= _numberOfTokens,
            "you do not own sufficient number of token id"
        );
        require(
            erc1155.isApprovedForAll(msg.sender, address(this)),
            "please approve the contract"
        );
        TokensOnSale[_semiNFTAddress][_id] = info(
            _price,
            _numberOfTokens,
            msg.sender,
            _tokensAcceptedAddress
        );
        emit SellToken(msg.sender, _id, _semiNFTAddress, _numberOfTokens);
    }

    function buyERC1155(
        uint256 _id,
        uint256 _numberOfTokens,
        address _tokenAddress
    ) external payable onSale(_tokenAddress, _id) {
        require(
            _numberOfTokens <= TokensOnSale[_tokenAddress][_id].numberOfTokens,
            "less numner of tokens available for this token id"
        );

        uint256 priceOfToken = TokensOnSale[_tokenAddress][_id].price *
            _numberOfTokens;
        uint256 commision = ((priceOfToken) / (10 ** (decimals + 2))) * feeCharge;

        if (
            TokensOnSale[_tokenAddress][_id].exchangeAcceptedAddress !=
            address(0)
        ) {
            address _exchangeAcceptedAddress = TokensOnSale[_tokenAddress][_id]
                .exchangeAcceptedAddress;
            address _tokenOwner = TokensOnSale[_tokenAddress][_id].tokenOwner;
            _exchangeERC20Tokens(
                _exchangeAcceptedAddress,
                commision,
                priceOfToken,
                _tokenOwner
            );
        } else {
            _ethExchange(commision, _id, priceOfToken, _tokenAddress);
        }

        IERC1155(_tokenAddress).safeTransferFrom(
            TokensOnSale[_tokenAddress][_id].tokenOwner,
            msg.sender,
            _id,
            _numberOfTokens,
            ""
        );
        if (
            _numberOfTokens == TokensOnSale[_tokenAddress][_id].numberOfTokens
        ) {
            delete TokensOnSale[_tokenAddress][_id];
        } else {
            TokensOnSale[_tokenAddress][_id].numberOfTokens =  TokensOnSale[_tokenAddress][_id].numberOfTokens - _numberOfTokens;
        }
        buyersToken.push(TokensOnSale[_tokenAddress][_id]
            .exchangeAcceptedAddress);
        emit BuyToken(msg.sender, _tokenAddress, _id);
    }

    function buyERC721(
        uint256 _id,
        address _tokenAddress
    ) external payable onSale(_tokenAddress, _id) {
        uint256 priceOfToken = TokensOnSale[_tokenAddress][_id].price;
        uint256 commision = ((priceOfToken) / (10 ** (decimals + 2))) * feeCharge;

        if (
            TokensOnSale[_tokenAddress][_id].exchangeAcceptedAddress !=
            address(0)
        ) {
            address _exchangeAcceptedAddress = TokensOnSale[_tokenAddress][_id]
                .exchangeAcceptedAddress;
            address _tokenOwner = TokensOnSale[_tokenAddress][_id].tokenOwner;
            _exchangeERC20Tokens(
                _exchangeAcceptedAddress,
                commision,
                priceOfToken,
                _tokenOwner
            );
        } else {
            _ethExchange(commision, _id, priceOfToken, _tokenAddress);
        }

        IERC721(_tokenAddress).safeTransferFrom(
            TokensOnSale[_tokenAddress][_id].tokenOwner,
            msg.sender,
            _id
        );
        delete TokensOnSale[_tokenAddress][_id];
        buyersToken.push(TokensOnSale[_tokenAddress][_id]
            .exchangeAcceptedAddress);
        emit BuyToken(msg.sender, _tokenAddress, _id);
    }

    function withdrawCommision() external onlyOwner {
        payable(marketPlaceOwner).transfer(address(this).balance);
        for (uint256 i = 0; i < buyersToken.length; ++i) {
            IERC20 erc20 = IERC20(buyersToken[i]);
            erc20.transfer(marketPlaceOwner, erc20.balanceOf(address(this)));
            delete buyersToken[i];
        }
    }

    function _exchangeERC20Tokens(
        address _exchangeAcceptedAddress,
        uint256 _commision,
        uint256 _priceOfToken,
        address _tokenOwner
    ) internal {
        IERC20 erc20 = IERC20(_exchangeAcceptedAddress);
        require(
            erc20.balanceOf(msg.sender) >= _priceOfToken,
            "you do not have sufficient balance"
        );
        require(
            erc20.allowance(msg.sender, address(this)) >= _priceOfToken,
            "please approve the contract"
        );
        erc20.transferFrom(msg.sender, _tokenOwner, _priceOfToken - _commision);
        erc20.transferFrom(msg.sender, address(this), _commision);
    }

    function _ethExchange(
        uint256 _commision,
        uint256 _id,
        uint256 _priceOfToken,
        address _tokenAddress
    ) internal {
        require(
            msg.value >= _priceOfToken,
            "please increase the amount entered"
        );
        payable(TokensOnSale[_tokenAddress][_id].tokenOwner).transfer(
            _priceOfToken - _commision
        );
        payable(address(this)).transfer(_commision);
    }

    function getTokenInfo(
        uint256 _id,
        address _tokenAddress
    ) external view returns (address, uint256, uint256) {
        return (
            TokensOnSale[_tokenAddress][_id].exchangeAcceptedAddress,
            TokensOnSale[_tokenAddress][_id].price,
            TokensOnSale[_tokenAddress][_id].numberOfTokens
        );
    }
}
