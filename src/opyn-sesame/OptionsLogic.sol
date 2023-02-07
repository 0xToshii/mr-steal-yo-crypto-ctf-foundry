// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


/// @dev Implements the logic for issuing, exercising issued options
contract OptionsLogic is Ownable, ERC20 {

    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /* represents floting point numbers, where number = value * 10 ** exponent
    i.e 0.1 = 10 * 10 ** -3 */
    struct Number {
        uint256 value;
        int32 exponent;
    }

    // Keeps track of the weighted collateral and weighted debt for each vault.
    struct Vault {
        uint256 collateral;
        uint256 oTokensIssued;
        uint256 underlying;
        bool owned;
    }

    mapping(address => Vault) internal vaults;

    address[] public vaultOwners;

    // The amount of insurance promised per oToken
    Number public strikePrice;

    // The amount of underlying that 1 oToken protects.
    Number public oTokenExchangeRate;

    // Exercise period starts at `(expiry - windowSize)` and ends at `expiry`
    uint256 internal windowSize;

    // The time of expiry of the options contract
    uint256 public expiry;

    // The precision of the collateral
    int32 public collateralExp = -18;

    // The precision of the underlying
    int32 public underlyingExp = -18;

    // The collateral asset (USDC)
    IERC20 public collateral;

    // The asset in which insurance is denominated in. (USDC)
    IERC20 public strike;

    // underlying is always ETH

    /**
     * @dev Throws if called Options contract is expired.
     */
    modifier notExpired() {
        require(!hasExpired(), "Options contract expired");
        _;
    }

    /**
    * @dev The underlying asset will always be ETH
    * @dev Precision for all assets & conversions is fixed to 1e18
    * @param _collateral The collateral asset (always USDC)
    * @param _strikePrice The amount of strike asset that will be paid out
    * @param _strike The asset in which the insurance is calculated (always USDC)
    * @param _expiry The time at which the insurance expires
    */
    constructor(
        IERC20 _collateral, // USDC
        uint256 _strikePrice, // amount USDC you can sell 1 ETH for
        IERC20 _strike, // USDC
        uint256 _expiry
    ) ERC20('oToken','oToken') {
        require(block.timestamp < _expiry, "Can't deploy an expired contract");
        require(_collateral == _strike,'invalid tokens');

        windowSize = _expiry; // negates window size
        expiry = _expiry;

        collateral = _collateral;

        oTokenExchangeRate = Number(1,-18);

        strikePrice = Number(_strikePrice, -18);
        strike = _strike;
    }

    /**
     * @notice Checks if a `owner` has already created a Vault
     * @param owner The address of the supposed owner
     * @return true or false
     */
    function hasVault(address owner) public view returns (bool) {
        return vaults[owner].owned;
    }

    /**
     * @notice Creates a new empty Vault and sets the owner of the vault to be the msg.sender.
     */
    function openVault() public notExpired returns (bool) {
        require(!hasVault(msg.sender), "Vault already created");

        vaults[msg.sender] = Vault(0, 0, 0, true);
        vaultOwners.push(msg.sender);

        return true;
    }

    /**
     * @dev Adds USDC collateral, which also mints an equivalent amount of oTokens to the user
     * Remember that adding ERC20 collateral even if no oTokens have been created can put the owner at a
     * risk of losing the collateral. Ensure that you issue and immediately sell the oTokens!
     * @param amt the amount of collateral to be transferred in.
     */
    function addERC20Collateral(uint256 amt)
        public
        notExpired
        returns (uint256)
    {
        collateral.safeTransferFrom(msg.sender, address(this), amt);
        
        require(hasVault(msg.sender), "Vault does not exist");
        Vault storage vault = vaults[msg.sender];

        uint256 oTokensToIssue = maxOTokensIssuable(amt); // fully collateralized
        uint256 newOTokensBalance = vault.oTokensIssued.add(oTokensToIssue);
        vault.oTokensIssued = newOTokensBalance;

        _mint(msg.sender, oTokensToIssue);

        vault.collateral = vault.collateral.add(amt);
        return vault.collateral;
    }

    /**
     * @notice Returns the amount of underlying to be transferred during an exercise call
     */
    function underlyingRequiredToExercise(uint256 oTokensToExercise)
        public
        view
        returns (uint256)
    {
        uint64 underlyingPerOTokenExp = uint64(
            uint32(oTokenExchangeRate.exponent - underlyingExp)
        );
        return oTokensToExercise.mul(10**underlyingPerOTokenExp);
    }

    /**
     * @notice Returns true if exercise can be called
     */
    function isExerciseWindow() public view returns (bool) {
        return ((block.timestamp >= expiry.sub(windowSize)) &&
            (block.timestamp < expiry));
    }

    /**
     * @notice Returns true if the oToken contract has expired
     */
    function hasExpired() public view returns (bool) {
        return (block.timestamp >= expiry);
    }

    /**
     * @notice Called by anyone holding the oTokens and underlying during the
     * exercise window i.e. from `expiry - windowSize` time to `expiry` time. The caller
     * transfers in their oTokens and corresponding amount of underlying and gets
     * `strikePrice * oTokens` amount of collateral out. The collateral paid out is taken from
     * the each vault owner starting with the first and iterating until the oTokens to exercise
     * are found.
     * NOTE: This uses a for loop and hence could run out of gas if the array passed in is too big!
     * @param oTokensToExercise the number of oTokens being exercised.
     * @param vaultsToExerciseFrom the array of vaults to exercise from.
     */
    function exercise(
        uint256 oTokensToExercise,
        address[] memory vaultsToExerciseFrom
    ) public payable {
        for (uint256 i = 0; i < vaultsToExerciseFrom.length; i++) {
            address vaultOwner = vaultsToExerciseFrom[i];
            require(
                hasVault(vaultOwner),
                "Cannot exercise from a vault that doesn't exist"
            );
            Vault storage vault = vaults[vaultOwner];
            if (oTokensToExercise == 0) {
                return;
            } else if (vault.oTokensIssued >= oTokensToExercise) {
                _exercise(oTokensToExercise, vaultOwner);
                return;
            } else {
                oTokensToExercise = oTokensToExercise.sub(vault.oTokensIssued);
                _exercise(vault.oTokensIssued, vaultOwner);
            }
        }
        require(
            oTokensToExercise == 0,
            "Specified vaults have insufficient collateral"
        );
    }

    /**
     * @notice after expiry, each vault holder can get back their proportional share of collateral
     * from vaults that they own.
     * @dev The owner gets all of their collateral back if no exercise event took their collateral.
     */
    function redeemVaultBalance() public {
        require(hasExpired(), "Can't collect collateral until expiry");
        require(hasVault(msg.sender), "Vault does not exist");

        // pay out owner their share
        Vault storage vault = vaults[msg.sender];

        // To deal with lower precision
        uint256 collateralToTransfer = vault.collateral;
        uint256 underlyingToTransfer = vault.underlying;

        vault.collateral = 0;
        vault.oTokensIssued = 0;
        vault.underlying = 0;

        transferCollateral(msg.sender, collateralToTransfer);
        transferUnderlying(msg.sender, underlyingToTransfer);
    }

    /**
     * @notice Called by anyone holding the oTokens and underlying during the
     * exercise window i.e. from `expiry - windowSize` time to `expiry` time. The caller
     * transfers in their oTokens and corresponding amount of underlying and gets
     * `strikePrice * oTokens` amount of collateral out. The collateral paid out is taken from
     * the specified vault holder. At the end of the expiry window, the vault holder can redeem their balance
     * of collateral. The vault owner can withdraw their underlying at any time.
     * The user has to allow the contract to handle their oTokens and underlying on his behalf before these functions are called.
     * @param oTokensToExercise the number of oTokens being exercised.
     * @param vaultToExerciseFrom the address of the vaultOwner to take collateral from.
     * @dev oTokenExchangeRate is the number of underlying tokens that 1 oToken protects.
     */
    function _exercise(
        uint256 oTokensToExercise,
        address vaultToExerciseFrom
    ) internal {
        // 1. before exercise window: revert
        require(
            isExerciseWindow(),
            "Can't exercise outside of the exercise window"
        );

        require(hasVault(vaultToExerciseFrom), "Vault does not exist");

        Vault storage vault = vaults[vaultToExerciseFrom];
        require(oTokensToExercise > 0, "Can't exercise 0 oTokens");
        // Check correct amount of oTokens passed in)
        require(
            oTokensToExercise <= vault.oTokensIssued,
            "Can't exercise more oTokens than the owner has"
        );
        // Ensure person calling has enough oTokens
        require(
            balanceOf(msg.sender) >= oTokensToExercise,
            "Not enough oTokens"
        );

        // 1. Check sufficient underlying
        // 1.1 update underlying balances
        uint256 amtUnderlyingToPay = underlyingRequiredToExercise(
            oTokensToExercise
        );
        vault.underlying = vault.underlying.add(amtUnderlyingToPay);

        // 2. Calculate Collateral to pay
        // 2.1 Payout enough collateral to get (strikePrice * oTokens) amount of collateral
        uint256 amtCollateralToPay = calculateCollateralToPay(
            oTokensToExercise,
            Number(1, 0)
        );

        uint256 totalCollateralToPay = amtCollateralToPay;
        require(
            totalCollateralToPay <= vault.collateral,
            "Vault underwater, can't exercise"
        );

        // 3. Update collateral + oToken balances
        vault.collateral = vault.collateral.sub(totalCollateralToPay);
        vault.oTokensIssued = vault.oTokensIssued.sub(oTokensToExercise);

        // 4. Transfer in underlying, burn oTokens + pay out collateral
        // 4.1 Transfer in underlying
        // underlying is always ETH
        require(msg.value == amtUnderlyingToPay, "Incorrect msg.value");

        // 4.2 burn oTokens
        _burn(msg.sender, oTokensToExercise);

        // 4.3 Pay out collateral
        transferCollateral(msg.sender, amtCollateralToPay);
    }

    /**
     * This function returns the maximum amount of oTokens that can safely be issued against the specified amount of collateral.
     * @param collateralAmt The amount of collateral against which oTokens will be issued.
     */
    function maxOTokensIssuable(uint256 collateralAmt)
        public
        view
        returns (uint256)
    {
        return calculateOTokens(collateralAmt, Number(1,0));
    }

    /**
     * @notice This function is used to calculate the amount of tokens that can be issued.
     * @dev The amount of oTokens is determined by:
     * oTokensIssued  <= collateralAmt * collateralToStrikePrice / (proportion * strikePrice)
     * @param collateralAmt The amount of collateral
     * @param proportion The proportion of the collateral to pay out. If 100% of collateral
     * should be paid out, pass in Number(1, 0). The proportion might be less than 100% if
     * you are calculating fees.
     */
    function calculateOTokens(uint256 collateralAmt, Number memory proportion)
        internal
        view
        returns (uint256)
    {
        uint256 collateralToEthPrice = getPrice(address(collateral));
        uint256 strikeToEthPrice = getPrice(address(strike));

        // oTokensIssued  <= collAmt * collateralToStrikePrice / (proportion * strikePrice)
        uint256 denomVal = proportion.value.mul(strikePrice.value);
        int32 denomExp = proportion.exponent + strikePrice.exponent;

        uint256 numeratorVal = (collateralAmt.mul(collateralToEthPrice)).div(
            strikeToEthPrice
        );
        int32 numeratorExp = collateralExp;

        uint256 exp = 0;
        uint256 numOptions = 0;

        if (numeratorExp < denomExp) {
            exp = uint256(uint32(denomExp - numeratorExp));
            numOptions = numeratorVal.div(denomVal.mul(10**exp));
        } else {
            exp = uint256(uint32(numeratorExp - denomExp));
            numOptions = numeratorVal.mul(10**exp).div(denomVal);
        }

        return numOptions;
    }

    /**
     * @notice This function calculates the amount of collateral to be paid out.
     * @dev The amount of collateral to paid out is determined by:
     * (proportion * strikePrice * strikeToCollateralPrice * oTokens) amount of collateral.
     * @param _oTokens The number of oTokens.
     * @param proportion The proportion of the collateral to pay out. If 100% of collateral
     * should be paid out, pass in Number(1, 0). The proportion might be less than 100% if
     * you are calculating fees.
     */
    function calculateCollateralToPay(
        uint256 _oTokens,
        Number memory proportion
    ) internal view returns (uint256) {
        // Get price from oracle
        uint256 collateralToEthPrice = getPrice(address(collateral));
        uint256 strikeToEthPrice = getPrice(address(strike));

        // calculate how much should be paid out
        uint256 amtCollateralToPayInEthNum = _oTokens
            .mul(strikePrice.value)
            .mul(proportion.value)
            .mul(strikeToEthPrice);
        int32 amtCollateralToPayExp = strikePrice.exponent +
            proportion.exponent -
            collateralExp;
        uint256 amtCollateralToPay = 0;
        if (amtCollateralToPayExp > 0) {
            uint32 exp = uint32(amtCollateralToPayExp);
            amtCollateralToPay = amtCollateralToPayInEthNum.mul(10**exp).div(
                collateralToEthPrice
            );
        } else {
            uint32 exp = uint32(-1 * amtCollateralToPayExp);
            amtCollateralToPay = (amtCollateralToPayInEthNum.div(10**exp)).div(
                collateralToEthPrice
            );
        }

        return amtCollateralToPay;
    }

    /// @dev Collateral is always USDC
    function transferCollateral(address _addr, uint256 _amt) internal {
        collateral.safeTransfer(_addr, _amt);
    }

    /// @dev Underlying is always ETH
    function transferUnderlying(address _addr, uint256 _amt) internal {
        payable(_addr).transfer(_amt);
    }

    /**
     * @notice This function gets the price ETH (wei) to asset price.
     * @param asset The address of the asset to get the price of
     */
    function getPrice(address asset) internal view returns (uint256) {
        if (address(collateral) == address(strike)) {
            return 1;
        } 
        // other irrelevant cases ...
    }

}