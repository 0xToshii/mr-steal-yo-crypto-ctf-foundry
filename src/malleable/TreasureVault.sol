// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


/// @dev Owner stores funds & allows select users to withdraw based on provided signatures
contract TreasureVault {

    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public constant TYPEHASH = keccak256("SendFundsWithAuth(uint256 amount,uint256 nonce)");

    mapping(bytes32 => bool) usedHash;

    address public immutable owner;

    constructor() {
        owner = msg.sender;

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("TreasureVault")),
                keccak256(bytes("1")),
                getChainid(),
                address(this)
            )
        );
    }

    receive() external payable {}

    /// @dev With signature from owner, caller can withdraw `amount` of funds
    /// @dev Changing `nonce` allows owner to create more than one valid signature
    function sendFundsWithAuth(
        uint256 amount, 
        uint256 nonce, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external {
        require(tx.origin == msg.sender,'EOA');

        bytes32 structHash = keccak256(abi.encode(TYPEHASH, amount, nonce));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory == owner,'invalid sig');

        bytes32 signatureHash = keccak256(abi.encodePacked(v, r, s));
        require(!usedHash[signatureHash],'sig reuse');
        usedHash[signatureHash]=true;

        (bool success,) = payable(msg.sender).call{value:amount}('');
        require(success);
    }

    /// @dev Remove funds and send to owner
    function removeFunds() external {
        require(msg.sender == owner,'invalid caller');

        (bool success,) = payable(msg.sender).call{value:address(this).balance}('');
        require(success);
    }

    function getChainid() public view returns (uint256) {
        return block.chainid;
    }

}