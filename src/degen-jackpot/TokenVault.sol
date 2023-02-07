// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "./OtherInterfaces.sol";
import "./OtherContracts.sol";


/// @dev Handles logic for ensuring FNFTs are backed by assets in the vault
contract TokenVault is ITokenVault, AccessControlEnumerable, RevestAccessControl {

    using SafeERC20 for IERC20;

    mapping(uint => IRevest.FNFTConfig) private fnfts;
    mapping(address => IRevest.TokenTracker) public tokenTrackers;

    uint private constant multiplierPrecision = 1 ether;

    constructor(address provider) RevestAccessControl(provider) {}

    function createFNFT(uint fnftId, IRevest.FNFTConfig memory fnftConfig, uint quantity, address from) external override {
        mapFNFTToToken(fnftId, fnftConfig);
        depositToken(fnftId, fnftConfig.depositAmount, quantity);
    }

    /**
     * Grab the current balance of this address in the ERC20 and update the multiplier accordingly
     */
    function updateBalance(uint fnftId, uint incomingDeposit) internal {
        IRevest.FNFTConfig storage fnft = fnfts[fnftId];
        address asset = fnft.asset;
        IRevest.TokenTracker storage tracker = tokenTrackers[asset];

        uint currentAmount;
        uint lastBal = tracker.lastBalance;

        if(asset != address(0)){
            currentAmount = IERC20(asset).balanceOf(address(this));
        } else {
            // Keep us from zeroing out zero assets
            currentAmount = lastBal;
        }
        tracker.lastMul = lastBal == 0 ? multiplierPrecision : multiplierPrecision * currentAmount / lastBal;
        tracker.lastBalance = currentAmount + incomingDeposit;
    }

    /**
     * This lines up the fnftId with its config and ensures that the fnftId -> config mapping
     * is only created if the proper tokens are deposited.
     * It does not handle the FNFT creation and assignment itself, that happens in Revest.sol
     * PRECONDITION: fnftId maps to fnftConfig, as done in CreateFNFT()
     */
    function depositToken(
        uint fnftId,
        uint transferAmount,
        uint quantity
    ) public override onlyRevestController {
        // Updates in advance, to handle rebasing tokens
        updateBalance(fnftId, quantity * transferAmount);
        IRevest.FNFTConfig storage fnft = fnfts[fnftId];
        fnft.depositMul = tokenTrackers[fnft.asset].lastMul;
    }

    function withdrawToken(
        uint fnftId,
        uint quantity,
        address user
    ) external override onlyRevestController {
        IRevest.FNFTConfig storage fnft = fnfts[fnftId];
        IRevest.TokenTracker storage tracker = tokenTrackers[fnft.asset];
        address asset = fnft.asset;

        // Update multiplier first
        updateBalance(fnftId, 0);

        uint withdrawAmount = fnft.depositAmount * quantity * tracker.lastMul / fnft.depositMul;
        tracker.lastBalance -= withdrawAmount;
        
        if(asset != address(0)) { // pipeTo removed
            IERC20(asset).safeTransfer(user, withdrawAmount);
        }

        if(getFNFTHandler().getSupply(fnftId) == 0) {
            removeFNFT(fnftId);
        }
    }

    function mapFNFTToToken(
        uint fnftId,
        IRevest.FNFTConfig memory fnftConfig
    ) public override onlyRevestController {
        // Gas optimizations
        fnfts[fnftId].asset =  fnftConfig.asset;
        fnfts[fnftId].depositAmount =  fnftConfig.depositAmount;
        if(fnftConfig.depositMul > 0) {
            fnfts[fnftId].depositMul = fnftConfig.depositMul;
        }
    }

    function removeFNFT(uint fnftId) internal {
        delete fnfts[fnftId];
    }

    // amount = amount per vault for new mapping
    function handleMultipleDeposits(
        uint fnftId,
        uint newFNFTId,
        uint amount
    ) external override onlyRevestController {
        require(amount >= fnfts[fnftId].depositAmount, 'E003');
        IRevest.FNFTConfig storage config = fnfts[fnftId];
        config.depositAmount = amount;
        mapFNFTToToken(fnftId, config);
        if(newFNFTId != 0) {
            mapFNFTToToken(newFNFTId, config);
        }
    }

    /**
     * Getters
     **/
    function getFNFT(uint fnftId) external view override returns (IRevest.FNFTConfig memory) {
        return fnfts[fnftId];
    }

}