// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


/// @dev deflationary token which burns 5% per transfer
contract MulaToken is ERC20, Ownable {

    constructor(
        string memory _name,
        string memory _symbol
    ) ERC20(
        _name,
        _symbol
    ) {}

    /// @dev mints specified amount for specified users
    function mintPerUser(
        address[] calldata users, 
        uint256[] calldata amounts
    ) external onlyOwner {
        for (uint256 i; i<users.length; ++i) {
            _mint(users[i],amounts[i]);
        }
    }

    /// @dev transferFrom with a 5% transfer tax
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);

        uint256 tax = amount * 5 / 100;
        _burn(from, tax);

        _transfer(from, to, amount-tax);
        return true;
    }

    /// @dev transfer with a 5% transfer tax
    function transfer(
        address to, 
        uint256 amount
    ) public override returns (bool) {
        address owner = _msgSender();

        uint256 tax = amount * 5 / 100;
        _burn(owner, tax);

        _transfer(owner, to, amount-tax);
        return true;
    } 

}