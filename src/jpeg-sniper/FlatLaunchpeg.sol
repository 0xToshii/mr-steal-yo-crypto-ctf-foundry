// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./BaseLaunchpegNFT.sol";


/// @dev hopegs NFT exchange wrapper to manage mint
contract FlatLaunchpeg is BaseLaunchpegNFT {

    enum Phase {
        NotStarted,
        PublicSale
    }

    modifier atPhase(Phase _phase) {
        if (currentPhase() != _phase) {
            revert Launchpeg__WrongPhase();
        }
        _;
    }

    constructor(
        uint256 _collectionSize,
        uint256 _maxBatchSize,
        uint256 _maxPerAddressDuringMint
    ) BaseLaunchpegNFT(
        _collectionSize,
        _maxBatchSize,
        _maxPerAddressDuringMint
    ) {}

    /// @notice Mint NFTs during the public sale
    /// @param _quantity Quantity of NFTs to mint
    function publicSaleMint(uint256 _quantity)
        external
        payable
        isEOA
        atPhase(Phase.PublicSale)
    {
        if (numberMinted(msg.sender) + _quantity > maxPerAddressDuringMint) {
            revert Launchpeg__CanNotMintThisMany();
        }
        if (totalSupply() + _quantity > collectionSize) {
            revert Launchpeg__MaxSupplyReached();
        }
        uint256 total = salePrice * _quantity;

        _mintForUser(msg.sender, _quantity);
        _refundIfOver(total);
    }

    /// @notice Returns the current phase
    /// @return phase Current phase
    function currentPhase() public view returns (Phase) {
        if (
            publicSaleStartTime == 0 ||
            block.timestamp < publicSaleStartTime
        ) {
            return Phase.NotStarted;
        } else {
            return Phase.PublicSale;
        }
    }

}