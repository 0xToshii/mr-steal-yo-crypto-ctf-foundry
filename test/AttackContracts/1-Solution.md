`FlatLaunchpeg` contract uses `isEOA` modifier (from `BaseLaunchNFT`) to check if the minter is an Externally Owned Account and not a smart contract.
This can be bypassed simply by using a smart contract with all the logic in the constructor, since `extcodesize()` returns 0 if the smart contract is empty,
but has logic implemented in the constructor. After that we have to bypass the error `Launchpeg__CanNotMintThisMany`. This error is raised if an address
mints more than `maxPerAddressDuringMint` allows, which is 5 in our case. We can bypass this error by transfering the minted NFTs to another address immediately
after minting them.
