// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./LaunchpegErrors.sol";


/// @dev base NFT contract
contract BaseLaunchpegNFT is ERC721, Ownable {

    using Counters for Counters.Counter;
    Counters.Counter private _tokenId;

    uint256 public collectionSize;
    uint256 public maxBatchSize;
    uint256 public salePrice; // free mint
    uint256 public maxPerAddressDuringMint;
    uint256 public publicSaleStartTime;

    modifier isEOA() {
        uint256 size;
        address sender = msg.sender;

        assembly {
            size := extcodesize(sender)
        }

        if (size > 0) revert Launchpeg__Unauthorized();
        _;
    }

    constructor(
        uint256 _collectionSize,
        uint256 _maxBatchSize,
        uint256 _maxPerAddressDuringMint
    ) ERC721('BOOTY','BOOTY') {
        collectionSize = _collectionSize;
        maxBatchSize = _maxBatchSize;
        maxPerAddressDuringMint = _maxPerAddressDuringMint;
        publicSaleStartTime = block.timestamp; // mint turned on this block
    }

    /// @notice Returns the number of NFTs minted by a specific address
    /// @param _owner The owner of the NFTs
    /// @return numberMinted Number of NFTs minted
    function numberMinted(address _owner)
        public
        view
        returns (uint256)
    {
        return balanceOf(_owner);
    }

    /// @dev returns the total amount minted
    function totalSupply() public view returns (uint256) {
        return _tokenId.current();
    }

    /// @dev mints n number of NFTs per user
    function _mintForUser(address to, uint256 quantity) internal {
        for (uint256 i=0; i<quantity; i++) {
            _mint(to, _tokenId.current());
            _tokenId.increment();
        }
    }

    /// @dev Verifies that enough funds have been sent by the sender and refunds the extra tokens if any
    /// @param _price The price paid by the sender for minting NFTs
    function _refundIfOver(uint256 _price) internal {
        if (msg.value < _price) {
            revert Launchpeg__NotEnoughFunds(msg.value);
        }
        if (msg.value > _price) {
            (bool success, ) = msg.sender.call{value: msg.value - _price}("");
            if (!success) {
                revert Launchpeg__TransferFailed();
            }
        }
    }

}