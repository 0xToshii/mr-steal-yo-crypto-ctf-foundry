// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./OtherInterfaces.sol";


contract RevestAccessControl is Ownable {

    IAddressRegistry internal addressesProvider;

    constructor(address provider) Ownable() {
        addressesProvider = IAddressRegistry(provider);
    }

    modifier onlyRevest() {
        require(_msgSender() != address(0), "E004");
        require(
                _msgSender() == addressesProvider.getLockManager() ||
                _msgSender() == addressesProvider.getTokenVault() ||
                _msgSender() == addressesProvider.getRevest(),
            "E016"
        );
        _;
    }

    modifier onlyRevestController() {
        require(_msgSender() != address(0), "E004");
        require(_msgSender() == addressesProvider.getRevest(), "E017");
        _;
    }

    modifier onlyTokenVault() {
        require(_msgSender() != address(0), "E004");
        require(_msgSender() == addressesProvider.getTokenVault(), "E017");
        _;
    }

    function setAddressRegistry(address registry) external onlyOwner {
        addressesProvider = IAddressRegistry(registry);
    }

    function getAdmin() internal view returns (address) {
        return addressesProvider.getAdmin();
    }

    function getRevest() internal view returns (IRevest) {
        return IRevest(addressesProvider.getRevest());
    }

    function getLockManager() internal view returns (ILockManager) {
        return ILockManager(addressesProvider.getLockManager());
    }

    function getTokenVault() internal view returns (ITokenVault) {
        return ITokenVault(addressesProvider.getTokenVault());
    }

    function getFNFTHandler() internal view returns (IFNFTHandler) {
        return IFNFTHandler(addressesProvider.getRevestFNFT());
    }

}

contract RevestReentrancyGuard is ReentrancyGuard {

    // Used to avoid reentrancy
    uint private constant MAX_INT = 0xFFFFFFFFFFFFFFFF;
    uint private currentId = MAX_INT;

    modifier revestNonReentrant(uint fnftId) {
        // On the first call to nonReentrant, _notEntered will be true
        require(fnftId != currentId, "E052");

        // Any calls to nonReentrant after this point will fail
        currentId = fnftId;

        _;

        currentId = MAX_INT;
    }

}

contract AddressRegistry is IAddressRegistry, Ownable {

    address private lockManager;
    address private tokenVault;
    address private revestFNFT;
    address private revestAddr;

    constructor() Ownable() {}

    function getAdmin() external view override returns (address) {
        return owner();
    }

    function getLockManager() external view override returns (address) {
        return lockManager;
    }

    function setLockManager(address manager) external override onlyOwner {
        lockManager = manager;
    }

    function getTokenVault() external view override returns (address) {
        return tokenVault;
    }

    function setTokenVault(address vault) external override onlyOwner {
        tokenVault = vault;
    }

    function getRevestFNFT() external view override returns (address) {
        return revestFNFT;
    }

    function setRevestFNFT(address fnft) external override onlyOwner {
        revestFNFT = fnft;
    }

    function getRevest() external view override returns (address) {
        return revestAddr;
    }

    function setRevest(address revest) external override onlyOwner {
        revestAddr = revest;
    }

}
