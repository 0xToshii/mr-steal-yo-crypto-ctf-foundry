// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/Pausable.sol";


/// @dev safu yield generation strategy
/// @dev this strategy takes in {want} & generates {want} using its yield generator
/// @dev the yield generator is abstracted away bc it's not relevant to the exploit
/// @dev therefore you will see unimplemented logic for interacting w/ the generator
contract SafuStrategy is Ownable, Pausable {

    using SafeERC20 for IERC20;
    using Address for address;

    address public want; // deposit & withdrawal token
    address public vault; // safu vault

    mapping (address => bool) public whitelist;

    modifier onlyWhitelisted() {
        require(whitelist[msg.sender] == true, "not whitelisted");
        _;
    }
     
    constructor(
        address _want
    ) {
        want = _want;
        whitelist[msg.sender] = true;
    }

    /// @dev set the vault associated w/ this strategy
    function setVault(address _vault) external onlyOwner {
        require(vault == address(0), "vault set");
        vault = _vault;
    }

    /// @dev functionality for updating the whitelist
    function addOrRemoveFromWhitelist(
        address add, 
        bool isAdd
    ) public onlyOwner {
        whitelist[add] = isAdd;
    } 
     
    /// @dev puts the funds to work
    /// @dev called whenever someone deposits into this strategy's vault contract
    function deposit() public whenNotPaused {
        // takes in the deposited funds & puts in yield generator
        // ...
    }

    /// @dev withdraws {want} and sends it to the vault
    /// @param _amount How much {want} to withdraw.
    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "not vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            // withdraws funds depositied into yield generator & sends back to this address
            // ...
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        IERC20(want).safeTransfer(vault, wantBal); 
    }

    /// @dev handles required functionality before vault deposits to strategy
    function beforeDeposit() external virtual {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            deposit();
            sellHarvest();
        }
    } 

    /// @dev runs a single instance of harvesting
    function harvest() external whenNotPaused onlyWhitelisted {
        require(!Address.isContract(msg.sender), "is contract");
        sellHarvest();
        deposit(); // places harvested funds back into the yield generator
    }

    /// @dev harvests {want} from the yield generator
    function sellHarvest() internal {
        // gathers all harvested funds from the yield generator & converts to {want}
        // ...
    }

    /// @dev calculates the total underlying {want} held by this strategy
    /// @dev takes into account funds at hand + funds allocated in yield generator
    /// @dev HOWEVER yield generator is abstracted so it is ignored here (0)
    function balanceOf() public view returns (uint256) {
        return balanceOfWant()+0; // yield generator balance is 0
    }

    /// @dev returns balance of {want} in this contract
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    /// @dev pauses strategy
    function pause() public onlyOwner {
        _pause();
    }

    /// @dev unpauses the strategy
    function unpause() external onlyOwner {
        _unpause();
    }

}