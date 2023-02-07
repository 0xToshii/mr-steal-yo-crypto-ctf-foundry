// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "./OtherInterfaces.sol";
import "./OtherContracts.sol";


/// @dev This is the entrypoint for the frontend
contract Revest is IRevest, AccessControlEnumerable, RevestAccessControl, RevestReentrancyGuard {

    using SafeERC20 for IERC20;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /**
     * @dev Primary constructor to create the Revest controller contract
     * Grants ADMIN and MINTER_ROLE to whoever creates the contract
     */
    constructor(address provider) RevestAccessControl(provider) {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());
    }

    function mintAddressLock(
        address trigger,
        bytes memory arguments,
        address[] memory recipients,
        uint[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig
    ) external override returns (uint) {
        uint fnftId = getFNFTHandler().getNextId();

        {
            IRevest.LockParam memory addressLock;
            addressLock.addressLock = trigger;
            addressLock.lockType = IRevest.LockType.AddressLock;
            // Get or create lock based on address which can trigger unlock, assign lock to ID
            uint lockId = getLockManager().createLock(fnftId, addressLock);
        }
        // This is a public call to a third-party contract. Must be done after everything else.
        // Safe for reentry
        doMint(recipients, quantities, fnftId, fnftConfig);

        return fnftId;
    }

    function withdrawFNFT(uint fnftId, uint quantity) external override revestNonReentrant(fnftId) {
        address fnftHandler = addressesProvider.getRevestFNFT();
        // Check if this many FNFTs exist in the first place for the given ID
        require(quantity <= IFNFTHandler(fnftHandler).getSupply(fnftId), "E022");
        // Check if the user making this call has this many FNFTs to cash in
        require(quantity <= IFNFTHandler(fnftHandler).getBalance(_msgSender(), fnftId), "E006");
        // Check if the user making this call has any FNFT's
        require(IFNFTHandler(fnftHandler).getBalance(_msgSender(), fnftId) > 0, "E032");

        IRevest.LockType lockType = getLockManager().lockTypes(fnftId);
        require(lockType != IRevest.LockType.DoesNotExist, "E007");
        require(getLockManager().unlockFNFT(fnftId, _msgSender()),"E019");
        // Burn the FNFTs being exchanged
        burn(_msgSender(), fnftId, quantity);
        getTokenVault().withdrawToken(fnftId, quantity, _msgSender());
    }

    function unlockFNFT(uint fnftId) external override {
        // Works for value locks or time locks
        IRevest.LockType lock = getLockManager().lockTypes(fnftId);
        require(lock == IRevest.LockType.AddressLock, "E008");
        require(getLockManager().unlockFNFT(fnftId, _msgSender()), "E056");
    }

    /**
     * Amount will be per FNFT. So total ERC20s needed is amount * quantity.
     * Users can deposit additional into their own
     * Otherwise, if not an owner, they must distribute to all FNFTs equally
     */
    function depositAdditionalToFNFT(
        uint fnftId,
        uint amount,
        uint quantity
    ) external override returns (uint) {
        IRevest.FNFTConfig memory fnft = getTokenVault().getFNFT(fnftId);
        require(fnftId < getFNFTHandler().getNextId(), "E007");
        require(quantity > 0, "E070");

        address vault = addressesProvider.getTokenVault();
        address handler = addressesProvider.getRevestFNFT();
        address lockHandler = addressesProvider.getLockManager();

        bool createNewSeries = false;
        {
            uint supply = IFNFTHandler(handler).getSupply(fnftId);

            uint balance = IFNFTHandler(handler).getBalance(_msgSender(), fnftId);

            if (quantity > balance) {
                require(quantity == supply, "E069");
            }
            else if (quantity < balance || balance < supply) {
                createNewSeries = true;
            }
        }

        uint lockId = ILockManager(lockHandler).fnftIdToLockId(fnftId);

        // Whether to split the new deposits into their own series, or to simply add to an existing series
        uint newFNFTId;
        if(createNewSeries) {
            // Split into a new series
            newFNFTId = IFNFTHandler(handler).getNextId();
            ILockManager(lockHandler).pointFNFTToLock(newFNFTId, lockId);
            burn(_msgSender(), fnftId, quantity);
            IFNFTHandler(handler).mint(_msgSender(), newFNFTId, quantity, "");
        } else {
            // Stay the same
            newFNFTId = 0; // Signals to handleMultipleDeposits()
        }

        // Will call updateBalance
        ITokenVault(vault).depositToken(fnftId, amount, quantity);
        // Now, we transfer to the token vault
        if(fnft.asset != address(0)){
            IERC20(fnft.asset).safeTransferFrom(_msgSender(), vault, quantity * amount);
        }

        ITokenVault(vault).handleMultipleDeposits(fnftId, newFNFTId, fnft.depositAmount + amount);

        return newFNFTId;
    }

    //
    // INTERNAL FUNCTIONS
    //

    function doMint(
        address[] memory recipients,
        uint[] memory quantities,
        uint fnftId,
        IRevest.FNFTConfig memory fnftConfig
    ) internal {
        bool isSingular;
        uint totalQuantity = quantities[0];
        {
            uint rec = recipients.length;
            uint quant = quantities.length;
            require(rec == quant, "recipients and quantities arrays must match");
            // Calculate total quantity
            isSingular = rec == 1;
            if(!isSingular) {
                for(uint i = 1; i < quant; i++) {
                    totalQuantity += quantities[i];
                }
            }
            require(totalQuantity > 0, "E003");
        }

        // Gas optimization
        address vault = addressesProvider.getTokenVault();

        // Create the FNFT and update accounting within TokenVault
        ITokenVault(vault).createFNFT(fnftId, fnftConfig, totalQuantity, _msgSender());

        // Now, we move the funds to token vault from the message sender
        if(fnftConfig.asset != address(0)){
            IERC20(fnftConfig.asset).safeTransferFrom(_msgSender(), vault, totalQuantity * fnftConfig.depositAmount);
        }
        // Mint NFT
        // Gas optimization
        if(!isSingular) {
            getFNFTHandler().mintBatchRec(recipients, quantities, fnftId, totalQuantity, '');
        } else {
            getFNFTHandler().mint(recipients[0], fnftId, quantities[0], '');
        }

    }

    function burn(
        address account,
        uint id,
        uint amount
    ) internal {
        address fnftHandler = addressesProvider.getRevestFNFT();
        require(IFNFTHandler(fnftHandler).getSupply(id) - amount >= 0, "E025");
        IFNFTHandler(fnftHandler).burn(account, id, amount);
    }

}