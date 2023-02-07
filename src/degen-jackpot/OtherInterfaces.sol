// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


// for FNFTHandler
interface IFNFTHandler  {
    function getSupply(uint fnftId) external view returns (uint);
    function getBalance(address tokenHolder, uint id) external view returns (uint);
    function getNextId() external view returns (uint);
    function mint(address account, uint id, uint amount, bytes memory data) external;
    function burn(address account, uint id, uint amount) external;
    function mintBatchRec(address[] memory recipients, uint[] memory quantities, uint id, uint newSupply, bytes memory data) external;
    function mintBatch(address to, uint[] memory ids, uint[] memory amounts, bytes memory data) external;
    function burnBatch(address account, uint[] memory ids, uint[] memory amounts) external;    
}

// for LockManager
interface ILockManager {
    function createLock(uint fnftId, IRevest.LockParam memory lock) external returns (uint);
    function getLock(uint lockId) external view returns (IRevest.Lock memory);
    function fnftIdToLockId(uint fnftId) external view returns (uint);
    function fnftIdToLock(uint fnftId) external view returns (IRevest.Lock memory);
    function lockTypes(uint tokenId) external view returns (IRevest.LockType);
    function unlockFNFT(uint fnftId, address sender) external returns (bool);
    function getLockMaturity(uint fnftId) external view returns (bool);
    function pointFNFTToLock(uint fnftId, uint lockId) external;
}

// for Revest
interface IRevest {
    struct FNFTConfig {
        address asset; // The token being stored
        uint depositAmount; // How many tokens
        uint depositMul; // Deposit multiplier
    }
    enum LockType {
        DoesNotExist,
        AddressLock
    }
    struct LockParam {
        address addressLock;
        LockType lockType;
    }
    struct Lock {
        address addressLock;
        LockType lockType;
        bool unlocked;
    }
    // Refers to the global balance for an ERC20, encompassing possibly many FNFTs
    struct TokenTracker {
        uint lastBalance;
        uint lastMul;
    }

    function mintAddressLock(
        address trigger,
        bytes memory arguments,
        address[] memory recipients,
        uint[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig
    ) external returns (uint);
    function withdrawFNFT(uint tokenUID, uint quantity) external;
    function unlockFNFT(uint tokenUID) external;
    function depositAdditionalToFNFT(
        uint fnftId,
        uint amount,
        uint quantity
    ) external returns (uint);
}

// for TokenVault
interface ITokenVault {
    function createFNFT(
        uint fnftId,
        IRevest.FNFTConfig memory fnftConfig,
        uint quantity,
        address from
    ) external;
    function withdrawToken(
        uint fnftId,
        uint quantity,
        address user
    ) external;
    function depositToken(
        uint fnftId,
        uint amount,
        uint quantity
    ) external;
    function mapFNFTToToken(
        uint fnftId,
        IRevest.FNFTConfig memory fnftConfig
    ) external;
    function handleMultipleDeposits(
        uint fnftId,
        uint newFNFTId,
        uint amount
    ) external;
    function getFNFT(uint fnftId) external view returns (IRevest.FNFTConfig memory);
}

// functionality to get addresses for all relevant contracts & admin
interface IAddressRegistry {
    function getAdmin() external view returns (address); // setAdmin done with Ownable
    function getLockManager() external view returns (address);
    function setLockManager(address manager) external;
    function getTokenVault() external view returns (address);
    function setTokenVault(address vault) external;
    function getRevestFNFT() external view returns (address);
    function setRevestFNFT(address fnft) external;
    function getRevest() external view returns (address);
    function setRevest(address revest) external;
}
