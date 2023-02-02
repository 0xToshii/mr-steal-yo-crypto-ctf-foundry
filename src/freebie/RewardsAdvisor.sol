//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./GovToken.sol";


interface IAdvisor {
    function owner() external returns (address);
    function delegatedTransferERC20(address token, address to, uint256 amount) external;
}

// @title Rewards Advisor
// @notice fractionalize balance 
contract RewardsAdvisor {

    using SafeERC20 for IERC20;

    address public owner;
    IERC20 public farm; // farm token
    GovToken public xfarm; // staked farm token

    modifier onlyOwner {
        require(msg.sender == owner, "only owner");
        _;
    }

    constructor(
        address _farm,
        address _xfarm
    ) {
        farm = IERC20(_farm);
        xfarm = GovToken(_xfarm);
        owner = msg.sender;
    }

    // @param farmDeposit Amount of FARM transfered from sender to RewardsAdvisor
    // @param to Address to which liquidity tokens are minted
    // @param from Address from which tokens are transferred 
    // @return shares Quantity of liquidity tokens minted as a result of deposit
    function deposit(
        uint256 farmDeposit,
        address payable from,
        address to
    ) external returns (uint256 shares) {
        require(farmDeposit > 0, "deposits must be nonzero");
        require(to != address(0) && to != address(this), "to");
        require(from != address(0) && from != address(this), "from");

        shares = farmDeposit;
        if (xfarm.totalSupply() != 0) {
            uint256 farmBalance = farm.balanceOf(address(this));
            shares = (shares * xfarm.totalSupply()) / farmBalance;
        }

        if (isContract(from)) {
            require(IAdvisor(from).owner() == msg.sender); // admin
            IAdvisor(from).delegatedTransferERC20(address(farm), address(this), farmDeposit);
        } else {
            require(from == msg.sender); // user
            farm.safeTransferFrom(from, address(this), farmDeposit);
        }

        xfarm.mint(to, shares);
    }

    // @param shares Number of governance shares to redeem for FARM
    // @param to Address to which redeemed pool assets are sent
    // @param from Address from which liquidity tokens are sent
    // @return rewards Amount of farm redeemed by the submitted liquidity tokens
    function withdraw(
        uint256 shares,
        address to,
        address payable from
    ) external returns (uint256 rewards) {
        require(shares > 0, "shares");
        require(to != address(0), "to");
        require(from != address(0), "from");

        require(from == msg.sender || IAdvisor(from).owner() == msg.sender, "owner");
        rewards = (farm.balanceOf(address(this)) * shares) / xfarm.totalSupply();

        farm.safeTransfer(to, rewards);
        xfarm.burn(from, shares);
    }

    function snapshot() external onlyOwner {
        xfarm.snapshot();
    }

    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    function transferTokenOwnership(address newOwner) external onlyOwner {
        xfarm.transferOwnership(newOwner); 
    }

    function isContract(address _addr) private returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }

}