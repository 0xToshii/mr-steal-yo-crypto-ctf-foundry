// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./OtherInterfaces.sol";
import "./OtherContracts.sol";


/// @dev Implements the logic for the address lock
contract LockManager is ILockManager, ReentrancyGuard, AccessControlEnumerable, RevestAccessControl {

    uint public numLocks = 0; // We increment this to get the lockId for each new lock created
    mapping(uint => uint) public override fnftIdToLockId;
    mapping(uint => IRevest.Lock) public locks; // maps lockId to locks

    constructor(address provider) RevestAccessControl(provider) {}

    /**
     * We access all lock properties by calling this method and then extracting data from the underlying struct
     * No need to write specialized getters for each portion
     */
    function fnftIdToLock(uint fnftId) public view override returns (IRevest.Lock memory) {
        return locks[fnftIdToLockId[fnftId]];
    }

    function getLock(uint lockId) external view override returns (IRevest.Lock memory) {
        return locks[lockId];
    }

    /**
     * Point new FNFT id to same lock without creating a new one
     */
    function pointFNFTToLock(uint fnftId, uint lockId) external override onlyRevest {
        fnftIdToLockId[fnftId] = lockId;
    }

    function createLock(uint fnftId, IRevest.LockParam memory lock) external override onlyRevest returns (uint) {
        // Extensive validation on creation
        require(lock.lockType != IRevest.LockType.DoesNotExist, "E058");
        IRevest.Lock storage newLock = locks[numLocks];
        newLock.lockType = lock.lockType;

        if (lock.lockType == IRevest.LockType.AddressLock) {
            require(lock.addressLock != address(0), "E004");
            newLock.addressLock = lock.addressLock;
        }
        else {
            require(false, "Invalid type");
        }
        fnftIdToLockId[fnftId] = numLocks;
        numLocks += 1;
        return numLocks - 1;
    }

    /**
     * @dev Sets the maturity of an address lock to mature – can only be called from main contract
     * if address, only if it is called by the address given permissions to
     * lockId - the ID of the FNFT to unlock
     * @return true if the caller is valid and the lock has been unlocked, false otherwise
     */
    function unlockFNFT(uint fnftId, address sender) external override onlyRevestController returns (bool) {
        uint lockId = fnftIdToLockId[fnftId];
        IRevest.Lock storage lock = locks[lockId];
        IRevest.LockType typeLock = lock.lockType;

        if (typeLock == IRevest.LockType.AddressLock) {
            address addLock = lock.addressLock;
            if (!lock.unlocked && (sender == addLock)) {
                lock.unlocked = true;
                lock.addressLock = address(0);
            }
        }
        return lock.unlocked;
    }

    /**
     * Return whether a lock of any type is mature.
     */
    function getLockMaturity(uint fnftId) public view override returns (bool) {
        IRevest.Lock memory lock = locks[fnftIdToLockId[fnftId]];

        if (lock.lockType == IRevest.LockType.AddressLock) {
            return lock.unlocked;
        }
        else {
            revert("E050");
        }
    }

    function lockTypes(uint tokenId) external view override returns (IRevest.LockType) {
        return fnftIdToLock(tokenId).lockType;
    }

}