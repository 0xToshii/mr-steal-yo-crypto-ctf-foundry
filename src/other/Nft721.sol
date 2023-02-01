// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";


/// @dev defines a basic ERC721 contract with minting
contract Nft721 is ERC721, Ownable {

    using Counters for Counters.Counter;
    Counters.Counter private _tokenId;

    constructor (
        string memory name,
        string memory symbol
    ) ERC721(name, symbol) {}

    /// @dev mints `quantity` number of NFTs for `to`
    function mintForUser(address to, uint256 quantity) external onlyOwner {
        for (uint256 i=0; i<quantity; ++i) {
            _mint(to, _tokenId.current());
            _tokenId.increment();
        }
    }

}