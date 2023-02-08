// SPDX-License-Identifier: MIT
pragma solidity ^0.4.24;

import "./MoneyMarketHelpers.sol";


contract MoneyMarket is Exponential, SafeToken {

    uint constant initialInterestIndex = 10 ** 18;
    uint constant minimumCollateralRatioMantissa = 11 * (10 ** 17); // 1.1

    /**
      * @notice `MoneyMarket` is the core Compound MoneyMarket contract
      */
    constructor() public {
        admin = msg.sender;
        collateralRatio = Exp({mantissa: 2 * mantissaOne}); // pretty high, but no borrows so doesn't matter
    }

    /**
      * @dev Administrator for this contract. Initially set in constructor, but can
      *      be changed by the admin itself.
      */
    address public admin;

    /**
      * @dev Container for customer balance information written to storage.
      *
      *      struct Balance {
      *        principal = customer total balance with accrued interest after applying the customer's most recent balance-changing action
      *        interestIndex = the total interestIndex as calculated after applying the customer's most recent balance-changing action
      *      }
      */
    struct Balance {
        uint principal;
        uint interestIndex;
    }

    /**
      * @dev 2-level map: customerAddress -> assetAddress -> balance for supplies
      */
    mapping(address => mapping(address => Balance)) public supplyBalances;

    /**
      * @dev 2-level map: customerAddress -> assetAddress -> balance for borrows
      */
    mapping(address => mapping(address => Balance)) public borrowBalances;

    /**
      * @dev Container for per-asset balance sheet and interest rate information written to storage, intended to be stored in a map where the asset address is the key
      *
      *      struct Market {
      *         isSupported = Whether this market is supported or not (not to be confused with the list of collateral assets)
      *         blockNumber = when the other values in this struct were calculated
      *         totalSupply = total amount of this asset supplied (in asset wei)
      *         supplyRateMantissa = the per-block interest rate for supplies of asset as of blockNumber, scaled by 10e18
      *         supplyIndex = the interest index for supplies of asset as of blockNumber; initialized in _supportMarket
      *         totalBorrows = total amount of this asset borrowed (in asset wei)
      *         borrowRateMantissa = the per-block interest rate for borrows of asset as of blockNumber, scaled by 10e18
      *         borrowIndex = the interest index for borrows of asset as of blockNumber; initialized in _supportMarket
      *     }
      */
    struct Market {
        bool isSupported;
        uint blockNumber;
        InterestRateModel interestRateModel;

        uint totalSupply;
        uint supplyRateMantissa;
        uint supplyIndex;

        uint totalBorrows;
        uint borrowRateMantissa;
        uint borrowIndex;
    }

    /**
      * @dev map: assetAddress -> Market
      */
    mapping(address => Market) public markets;

    /**
      * @dev list: collateralMarkets
      */
    address[] public collateralMarkets;

    /**
      * @dev The collateral ratio that borrows must maintain (e.g. 2 implies 2:1). This
      *      is initially set in the constructor, but can be changed by the admin.
      */
    Exp public collateralRatio;

    /**
      * @dev flag for whether or not contract is paused
      *
      */
    bool public paused;

    /**
      * @dev Simple function to calculate min between two numbers.
      */
    function min(uint a, uint b) pure internal returns (uint) {
        if (a < b) {
            return a;
        } else {
            return b;
        }
    }

    /**
      * @dev Function to simply retrieve block number
      *      This exists mainly for inheriting test contracts to stub this result.
      */
    function getBlockNumber() internal view returns (uint) {
        return block.number;
    }

    /**
      * @dev Adds a given asset to the list of collateral markets. This operation is impossible to reverse.
      *      Note: this will not add the asset if it already exists.
      */
    function addCollateralMarket(address asset) internal {
        for (uint i = 0; i < collateralMarkets.length; i++) {
            if (collateralMarkets[i] == asset) {
                return;
            }
        }

        collateralMarkets.push(asset);
    }

    /**
      * @notice Supports a given market (asset) for use with Compound
      * @dev Admin function to add support for a market
      * @param asset Asset to support; MUST already have a non-zero price set
      * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
      */
    function _supportMarket(address asset) public returns (uint) {
        // Check caller = admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SUPPORT_MARKET_OWNER_CHECK);
        }

        (Error err, Exp memory assetPrice) = fetchAssetPrice(asset);
        if (err != Error.NO_ERROR) {
            return fail(err, FailureInfo.SUPPORT_MARKET_FETCH_PRICE_FAILED);
        }

        if (isZeroExp(assetPrice)) {
            return fail(Error.ASSET_NOT_PRICED, FailureInfo.SUPPORT_MARKET_PRICE_CHECK);
        }

        // NOTE: interest rate model is fixed for all assets - supply and borrow rates will always be 
        // the same because the logic for borrowing is not included in this contract
        markets[asset].interestRateModel = new InterestRateModel();

        // Append asset to collateralAssets if not set
        addCollateralMarket(asset);

        // Set market isSupported to true
        markets[asset].isSupported = true;

        // Default supply and borrow index to 1e18
        if (markets[asset].supplyIndex == 0) {
            markets[asset].supplyIndex = initialInterestIndex;
        }

        if (markets[asset].borrowIndex == 0) {
            markets[asset].borrowIndex = initialInterestIndex;
        }

        // supplyRateMantissa and borrowRateMantissa are implicitly set to 0 here

        return uint(Error.NO_ERROR);
    }

    /**
      * @dev fetches the price of asset from the PriceOracle and converts it to Exp
      * THIS IS OBVIOUSLY INVALID - but there is only a single asset WLed, therefore relative pricing does
      * not matter in this case, and so the price for that one asset will be arbitrarily fixed - normally
      * this function would make a call to the oracle and get the value of the asset in ETH
      */
    function fetchAssetPrice(address asset) internal view returns (Error, Exp memory) {
        return (Error.NO_ERROR, Exp({mantissa: 10 ** 18})); // equivalent to 1/1 pricing of asset to ETH
    }

    /**
      * @dev Gets the price for the amount specified of the given asset.
      */
    function getPriceForAssetAmount(address asset, uint assetAmount) internal view returns (Error, Exp memory)  {
        (Error err, Exp memory assetPrice) = fetchAssetPrice(asset);
        if (err != Error.NO_ERROR) {
            return (err, Exp({mantissa: 0}));
        }

        if (isZeroExp(assetPrice)) {
            return (Error.MISSING_ASSET_PRICE, Exp({mantissa: 0}));
        }

        return mulScalar(assetPrice, assetAmount); // assetAmountWei * oraclePrice = assetValueInEth
    }

    /**
      * @dev Calculates a new supply index based on the prevailing interest rates applied over time
      *      This is defined as `we multiply the most recent supply index by (1 + blocks times rate)`
      */
    function calculateInterestIndex(uint startingInterestIndex, uint interestRateMantissa, uint blockStart, uint blockEnd) pure internal returns (Error, uint) {

        // Get the block delta
        (Error err0, uint blockDelta) = sub(blockEnd, blockStart);
        if (err0 != Error.NO_ERROR) {
            return (err0, 0);
        }

        // Scale the interest rate times number of blocks
        // Note: Doing Exp construction inline to avoid `CompilerError: Stack too deep, try removing local variables.`
        (Error err1, Exp memory blocksTimesRate) = mulScalar(Exp({mantissa: interestRateMantissa}), blockDelta);
        if (err1 != Error.NO_ERROR) {
            return (err1, 0);
        }

        // Add one to that result (which is really Exp({mantissa: expScale}) which equals 1.0)
        (Error err2, Exp memory onePlusBlocksTimesRate) = addExp(blocksTimesRate, Exp({mantissa: mantissaOne}));
        if (err2 != Error.NO_ERROR) {
            return (err2, 0);
        }

        // Then scale that accumulated interest by the old interest index to get the new interest index
        (Error err3, Exp memory newInterestIndexExp) = mulScalar(onePlusBlocksTimesRate, startingInterestIndex);
        if (err3 != Error.NO_ERROR) {
            return (err3, 0);
        }

        // Finally, truncate the interest index. This works only if interest index starts large enough
        // that is can be accurately represented with a whole number.
        return (Error.NO_ERROR, truncate(newInterestIndexExp));
    }

    /**
      * @dev Calculates a new balance based on a previous balance and a pair of interest indices
      *      This is defined as: `The user's last balance checkpoint is multiplied by the currentSupplyIndex
      *      value and divided by the user's checkpoint index value`
      *
      *      TODO: Is there a way to handle this that is less likely to overflow?
      */
    function calculateBalance(uint startingBalance, uint interestIndexStart, uint interestIndexEnd) pure internal returns (Error, uint) {
        if (startingBalance == 0) {
            // We are accumulating interest on any previous balance; if there's no previous balance, then there is
            // nothing to accumulate.
            return (Error.NO_ERROR, 0);
        }
        (Error err0, uint balanceTimesIndex) = mul(startingBalance, interestIndexEnd);
        if (err0 != Error.NO_ERROR) {
            return (err0, 0);
        }

        return div(balanceTimesIndex, interestIndexStart);
    }

    /**
      * The `SupplyLocalVars` struct is used internally in the `supply` function.
      *
      * To avoid solidity limits on the number of local variables we:
      * 1. Use a struct to hold local computation localResults
      * 2. Re-use a single variable for Error returns. (This is required with 1 because variable binding to tuple localResults
      *    requires either both to be declared inline or both to be previously declared.
      * 3. Re-use a boolean error-like return variable.
      */
    struct SupplyLocalVars {
        uint startingBalance;
        uint newSupplyIndex;
        uint userSupplyCurrent;
        uint userSupplyUpdated;
        uint newTotalSupply;
        uint currentCash;
        uint updatedCash;
        uint newSupplyRateMantissa;
        uint newBorrowIndex;
        uint newBorrowRateMantissa;
    }

    /**
      * @notice supply `amount` of `asset` (which must be supported) to `msg.sender` in the protocol
      * @dev add amount of supported asset to msg.sender's account
      * @param asset The market asset to supply
      * @param amount The amount to supply
      * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
      */
    function supply(address asset, uint amount) public returns (uint) {
        if (paused) {
            return fail(Error.CONTRACT_PAUSED, FailureInfo.SUPPLY_CONTRACT_PAUSED);
        }

        Market storage market = markets[asset];
        Balance storage balance = supplyBalances[msg.sender][asset];

        SupplyLocalVars memory localResults; // Holds all our uint calculation results
        Error err; // Re-used for every function call that includes an Error in its return value(s).
        uint rateCalculationResultCode; // Used for 2 interest rate calculation calls

        // Fail if market not supported
        if (!market.isSupported) {
            return fail(Error.MARKET_NOT_SUPPORTED, FailureInfo.SUPPLY_MARKET_NOT_SUPPORTED);
        }

        // Fail gracefully if asset is not approved or has insufficient balance
        err = checkTransferIn(asset, msg.sender, amount);
        if (err != Error.NO_ERROR) {
            return fail(err, FailureInfo.SUPPLY_TRANSFER_IN_NOT_POSSIBLE);
        }

        // We calculate the newSupplyIndex, user's supplyCurrent and supplyUpdated for the asset
        (err, localResults.newSupplyIndex) = calculateInterestIndex(market.supplyIndex, market.supplyRateMantissa, market.blockNumber, getBlockNumber());
        if (err != Error.NO_ERROR) {
            return fail(err, FailureInfo.SUPPLY_NEW_SUPPLY_INDEX_CALCULATION_FAILED);
        }

        (err, localResults.userSupplyCurrent) = calculateBalance(balance.principal, balance.interestIndex, localResults.newSupplyIndex);
        if (err != Error.NO_ERROR) {
            return fail(err, FailureInfo.SUPPLY_ACCUMULATED_BALANCE_CALCULATION_FAILED);
        }

        (err, localResults.userSupplyUpdated) = add(localResults.userSupplyCurrent, amount);
        if (err != Error.NO_ERROR) {
            return fail(err, FailureInfo.SUPPLY_NEW_TOTAL_BALANCE_CALCULATION_FAILED);
        }

        // We calculate the protocol's totalSupply by subtracting the user's prior checkpointed balance, adding user's updated supply
        // basically when a user updates their asset balance, the totalSupply now includes that user's accumulated interest for the asset
        (err, localResults.newTotalSupply) = addThenSub(market.totalSupply, localResults.userSupplyUpdated, balance.principal);
        if (err != Error.NO_ERROR) {
            return fail(err, FailureInfo.SUPPLY_NEW_TOTAL_SUPPLY_CALCULATION_FAILED);
        }

        // We need to calculate what the updated cash will be after we transfer in from user
        localResults.currentCash = getCash(asset);

        (err, localResults.updatedCash) = add(localResults.currentCash, amount);
        if (err != Error.NO_ERROR) {
            return fail(err, FailureInfo.SUPPLY_NEW_TOTAL_CASH_CALCULATION_FAILED);
        }

        // The utilization rate has changed! We calculate a new supply index and borrow index for the asset, and save it.
        (rateCalculationResultCode, localResults.newSupplyRateMantissa) = market.interestRateModel.getSupplyRate(asset, localResults.updatedCash, market.totalBorrows);
        if (rateCalculationResultCode != 0) {
            return failOpaque(FailureInfo.SUPPLY_NEW_SUPPLY_RATE_CALCULATION_FAILED, rateCalculationResultCode);
        }

        // We calculate the newBorrowIndex (we already had newSupplyIndex)
        (err, localResults.newBorrowIndex) = calculateInterestIndex(market.borrowIndex, market.borrowRateMantissa, market.blockNumber, getBlockNumber());
        if (err != Error.NO_ERROR) {
            return fail(err, FailureInfo.SUPPLY_NEW_BORROW_INDEX_CALCULATION_FAILED);
        }

        (rateCalculationResultCode, localResults.newBorrowRateMantissa) = market.interestRateModel.getBorrowRate(asset, localResults.updatedCash, market.totalBorrows);
        if (rateCalculationResultCode != 0) {
            return failOpaque(FailureInfo.SUPPLY_NEW_BORROW_RATE_CALCULATION_FAILED, rateCalculationResultCode);
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        // We ERC-20 transfer the asset into the protocol (note: pre-conditions already checked above)
        err = doTransferIn(asset, msg.sender, amount);
        if (err != Error.NO_ERROR) {
            // This is safe since it's our first interaction and it didn't do anything if it failed
            return fail(err, FailureInfo.SUPPLY_TRANSFER_IN_FAILED);
        }

        // Save market updates
        market.blockNumber = getBlockNumber();
        market.totalSupply =  localResults.newTotalSupply;
        market.supplyRateMantissa = localResults.newSupplyRateMantissa;
        market.supplyIndex = localResults.newSupplyIndex;
        market.borrowRateMantissa = localResults.newBorrowRateMantissa;
        market.borrowIndex = localResults.newBorrowIndex;

        // Save user updates
        localResults.startingBalance = balance.principal;
        balance.principal = localResults.userSupplyUpdated;
        balance.interestIndex = localResults.newSupplyIndex;

        return uint(Error.NO_ERROR); // success
    }

    struct AccountValueLocalVars {
        address assetAddress;
        uint collateralMarketsLength;

        uint newSupplyIndex;
        uint userSupplyCurrent;
        Exp supplyTotalValue;
        Exp sumSupplies;

        uint newBorrowIndex;
        uint userBorrowCurrent;
        Exp borrowTotalValue;
        Exp sumBorrows;
    }

    /**
      * @dev Gets the user's account liquidity and account shortfall balances. This includes
      *      any accumulated interest thus far but does NOT actually update anything in
      *      storage, it simply calculates the account liquidity and shortfall with liquidity being
      *      returned as the first Exp, ie (Error, accountLiquidity, accountShortfall).
      * NOTE: borrowing is not implemented, so sum of borrows will always be 0
      */
    function calculateAccountLiquidity(address userAddress) internal view returns (Error, Exp memory, Exp memory) {
        Error err;
        uint sumSupplyValuesMantissa;
        uint sumBorrowValuesMantissa;
        (err, sumSupplyValuesMantissa, sumBorrowValuesMantissa) = calculateAccountValuesInternal(userAddress);
        if (err != Error.NO_ERROR) {
            return(err, Exp({mantissa: 0}), Exp({mantissa: 0}));
        }

        Exp memory result;
        
        Exp memory sumSupplyValuesFinal = Exp({mantissa: sumSupplyValuesMantissa});
        Exp memory sumBorrowValuesFinal; // need to apply collateral ratio

        (err, sumBorrowValuesFinal) = mulExp(collateralRatio, Exp({mantissa: sumBorrowValuesMantissa}));
        if (err != Error.NO_ERROR) {
            return (err, Exp({mantissa: 0}), Exp({mantissa: 0}));
        }

        // if sumSupplies < sumBorrows, then the user is under collateralized and has account shortfall.
        // else the user meets the collateral ratio and has account liquidity.
        if (lessThanExp(sumSupplyValuesFinal, sumBorrowValuesFinal)) {
            // accountShortfall = borrows - supplies
            (err, result) = subExp(sumBorrowValuesFinal, sumSupplyValuesFinal);
            assert(err == Error.NO_ERROR); // Note: we have checked that sumBorrows is greater than sumSupplies directly above, therefore `subExp` cannot fail.

            return (Error.NO_ERROR, Exp({mantissa: 0}), result);
        } else {
            // accountLiquidity = supplies - borrows
            (err, result) = subExp(sumSupplyValuesFinal, sumBorrowValuesFinal);
            assert(err == Error.NO_ERROR); // Note: we have checked that sumSupplies is greater than sumBorrows directly above, therefore `subExp` cannot fail.

            return (Error.NO_ERROR, result, Exp({mantissa: 0}));
        }
    }

    /**
      * @notice Gets the ETH values of the user's accumulated supply and borrow balances, scaled by 10e18.
      *         This includes any accumulated interest thus far but does NOT actually update anything in
      *         storage
      * @dev Gets ETH values of accumulated supply and borrow balances
      * @param userAddress account for which to sum values
      * @return (error code, sum ETH value of supplies scaled by 10e18, sum ETH value of borrows scaled by 10e18)
      * TODO: Possibly should add a Min(500, collateralMarkets.length) for extra safety
      * TODO: To help save gas we could think about using the current Market.interestIndex
      *       accumulate interest rather than calculating it
      */
    function calculateAccountValuesInternal(address userAddress) internal view returns (Error, uint, uint) {
        
        /** By definition, all collateralMarkets are those that contribute to the user's
          * liquidity and shortfall so we need only loop through those markets.
          * To handle avoiding intermediate negative results, we will sum all the user's
          * supply balances and borrow balances (with collateral ratio) separately and then
          * subtract the sums at the end.
          */

        AccountValueLocalVars memory localResults; // Re-used for all intermediate results
        localResults.sumSupplies = Exp({mantissa: 0});
        localResults.sumBorrows = Exp({mantissa: 0});
        Error err; // Re-used for all intermediate errors
        localResults.collateralMarketsLength = collateralMarkets.length;

        for (uint i = 0; i < localResults.collateralMarketsLength; i++) {
            localResults.assetAddress = collateralMarkets[i];
            Market storage currentMarket = markets[localResults.assetAddress];
            Balance storage supplyBalance = supplyBalances[userAddress][localResults.assetAddress];
            Balance storage borrowBalance = borrowBalances[userAddress][localResults.assetAddress];

            if (supplyBalance.principal > 0) {
                // We calculate the newSupplyIndex and user’s supplyCurrent (includes interest)
                (err, localResults.newSupplyIndex) = calculateInterestIndex(currentMarket.supplyIndex, currentMarket.supplyRateMantissa, currentMarket.blockNumber, getBlockNumber());
                if (err != Error.NO_ERROR) {
                    return (err, 0, 0);
                }

                (err, localResults.userSupplyCurrent) = calculateBalance(supplyBalance.principal, supplyBalance.interestIndex, localResults.newSupplyIndex);
                if (err != Error.NO_ERROR) {
                    return (err, 0, 0);
                }

                // We have the user's supply balance with interest so let's multiply by the asset price to get the total value
                (err, localResults.supplyTotalValue) = getPriceForAssetAmount(localResults.assetAddress, localResults.userSupplyCurrent); // supplyCurrent * oraclePrice = supplyValueInEth
                if (err != Error.NO_ERROR) {
                    return (err, 0, 0);
                }

                // Add this to our running sum of supplies
                (err, localResults.sumSupplies) = addExp(localResults.supplyTotalValue, localResults.sumSupplies);
                if (err != Error.NO_ERROR) {
                    return (err, 0, 0);
                }
            }

            if (borrowBalance.principal > 0) {
                // We perform a similar actions to get the user's borrow balance
                (err, localResults.newBorrowIndex) = calculateInterestIndex(currentMarket.borrowIndex, currentMarket.borrowRateMantissa, currentMarket.blockNumber, getBlockNumber());
                if (err != Error.NO_ERROR) {
                    return (err, 0, 0);
                }

                (err, localResults.userBorrowCurrent) = calculateBalance(borrowBalance.principal, borrowBalance.interestIndex, localResults.newBorrowIndex);
                if (err != Error.NO_ERROR) {
                    return (err, 0, 0);
                }

                // In the case of borrow, we multiply the borrow value by the collateral ratio
                (err, localResults.borrowTotalValue) = getPriceForAssetAmount(localResults.assetAddress, localResults.userBorrowCurrent); // ( borrowCurrent* oraclePrice * collateralRatio) = borrowTotalValueInEth
                if (err != Error.NO_ERROR) {
                    return (err, 0, 0);
                }

                // Add this to our running sum of borrows
                (err, localResults.sumBorrows) = addExp(localResults.borrowTotalValue, localResults.sumBorrows);
                if (err != Error.NO_ERROR) {
                    return (err, 0, 0);
                }
            }
        }
        
        return (Error.NO_ERROR, localResults.sumSupplies.mantissa, localResults.sumBorrows.mantissa);
    }

    /**
      * @dev Gets the amount of the specified asset given the specified Eth value
      *      ethValue / oraclePrice = assetAmountWei
      *      If there's no oraclePrice, this returns (Error.DIVISION_BY_ZERO, 0)
      */
    function getAssetAmountForValue(address asset, Exp ethValue) internal view returns (Error, uint) {
        Error err;
        Exp memory assetPrice;
        Exp memory assetAmount;

        (err, assetPrice) = fetchAssetPrice(asset);
        if (err != Error.NO_ERROR) {
            return (err, 0);
        }

        (err, assetAmount) = divExp(ethValue, assetPrice);
        if (err != Error.NO_ERROR) {
            return (err, 0);
        }

        return (Error.NO_ERROR, truncate(assetAmount));
    }

    struct WithdrawLocalVars {
        uint withdrawAmount;
        uint startingBalance;
        uint newSupplyIndex;
        uint userSupplyCurrent;
        uint userSupplyUpdated;
        uint newTotalSupply;
        uint currentCash;
        uint updatedCash;
        uint newSupplyRateMantissa;
        uint newBorrowIndex;
        uint newBorrowRateMantissa;

        Exp accountLiquidity;
        Exp accountShortfall;
        Exp ethValueOfWithdrawal;
        uint withdrawCapacity;
    }

    /**
      * @notice withdraw `amount` of `asset` from sender's account to sender's address
      * @dev withdraw `amount` of `asset` from msg.sender's account to msg.sender
      * @param asset The market asset to withdraw
      * @param requestedAmount The amount to withdraw (or -1 for max)
      * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
      */
    function withdraw(address asset, uint requestedAmount) public returns (uint) {
        if (paused) {
            return fail(Error.CONTRACT_PAUSED, FailureInfo.WITHDRAW_CONTRACT_PAUSED);
        }

        Market storage market = markets[asset];
        Balance storage supplyBalance = supplyBalances[msg.sender][asset];

        WithdrawLocalVars memory localResults; // Holds all our calculation results
        Error err; // Re-used for every function call that includes an Error in its return value(s).
        uint rateCalculationResultCode; // Used for 2 interest rate calculation calls

        // We calculate the user's accountLiquidity and accountShortfall.
        (err, localResults.accountLiquidity, localResults.accountShortfall) = calculateAccountLiquidity(msg.sender);
        if (err != Error.NO_ERROR) {
            return fail(err, FailureInfo.WITHDRAW_ACCOUNT_LIQUIDITY_CALCULATION_FAILED);
        }

        // We calculate the newSupplyIndex, user's supplyCurrent and supplyUpdated for the asset
        (err, localResults.newSupplyIndex) = calculateInterestIndex(market.supplyIndex, market.supplyRateMantissa, market.blockNumber, getBlockNumber());
        if (err != Error.NO_ERROR) {
            return fail(err, FailureInfo.WITHDRAW_NEW_SUPPLY_INDEX_CALCULATION_FAILED);
        }

        (err, localResults.userSupplyCurrent) = calculateBalance(supplyBalance.principal, supplyBalance.interestIndex, localResults.newSupplyIndex);
        if (err != Error.NO_ERROR) {
            return fail(err, FailureInfo.WITHDRAW_ACCUMULATED_BALANCE_CALCULATION_FAILED);
        }

        // If the user specifies -1 amount to withdraw ("max"),  withdrawAmount => the lesser of withdrawCapacity and supplyCurrent
        if (requestedAmount == uint(-1)) {
            (err, localResults.withdrawCapacity) = getAssetAmountForValue(asset, localResults.accountLiquidity);
            if (err != Error.NO_ERROR) {
                return fail(err, FailureInfo.WITHDRAW_CAPACITY_CALCULATION_FAILED);
            }
            localResults.withdrawAmount = min(localResults.withdrawCapacity, localResults.userSupplyCurrent);
        } else {
            localResults.withdrawAmount = requestedAmount;
        }

        // From here on we should NOT use requestedAmount.

        // Fail gracefully if protocol has insufficient cash
        // If protocol has insufficient cash, the sub operation will underflow.
        localResults.currentCash = getCash(asset);
        (err, localResults.updatedCash) = sub(localResults.currentCash, localResults.withdrawAmount);
        if (err != Error.NO_ERROR) {
            return fail(Error.TOKEN_INSUFFICIENT_CASH, FailureInfo.WITHDRAW_TRANSFER_OUT_NOT_POSSIBLE);
        }

        // We check that the amount is less than or equal to supplyCurrent
        // If amount is greater than supplyCurrent, this will fail with Error.INTEGER_UNDERFLOW
        (err, localResults.userSupplyUpdated) = sub(localResults.userSupplyCurrent, localResults.withdrawAmount);
        if (err != Error.NO_ERROR) {
            return fail(Error.INSUFFICIENT_BALANCE, FailureInfo.WITHDRAW_NEW_TOTAL_BALANCE_CALCULATION_FAILED);
        }

        // Fail if customer already has a shortfall
        if (!isZeroExp(localResults.accountShortfall)) {
            return fail(Error.INSUFFICIENT_LIQUIDITY, FailureInfo.WITHDRAW_ACCOUNT_SHORTFALL_PRESENT);
        }

        // We want to know the user's withdrawCapacity, denominated in the asset
        // Customer's withdrawCapacity of asset is (accountLiquidity in Eth)/ (price of asset in Eth)
        // Equivalently, we calculate the eth value of the withdrawal amount and compare it directly to the accountLiquidity in Eth
        (err, localResults.ethValueOfWithdrawal) = getPriceForAssetAmount(asset, localResults.withdrawAmount); // amount * oraclePrice = ethValueOfWithdrawal
        if (err != Error.NO_ERROR) {
            return fail(err, FailureInfo.WITHDRAW_AMOUNT_VALUE_CALCULATION_FAILED);
        }

        // We check that the amount is less than withdrawCapacity (here), and less than or equal to supplyCurrent (below)
        if (lessThanExp(localResults.accountLiquidity, localResults.ethValueOfWithdrawal) ) {
            return fail(Error.INSUFFICIENT_LIQUIDITY, FailureInfo.WITHDRAW_AMOUNT_LIQUIDITY_SHORTFALL);
        }

        // We calculate the protocol's totalSupply by subtracting the user's prior checkpointed balance, adding user's updated supply.
        // Note that, even though the customer is withdrawing, if they've accumulated a lot of interest since their last
        // action, the updated balance *could* be higher than the prior checkpointed balance.
        (err, localResults.newTotalSupply) = addThenSub(market.totalSupply, localResults.userSupplyUpdated, supplyBalance.principal);
        if (err != Error.NO_ERROR) {
            return fail(err, FailureInfo.WITHDRAW_NEW_TOTAL_SUPPLY_CALCULATION_FAILED);
        }

        // The utilization rate has changed! We calculate a new supply index and borrow index for the asset, and save it.
        (rateCalculationResultCode, localResults.newSupplyRateMantissa) = market.interestRateModel.getSupplyRate(asset, localResults.updatedCash, market.totalBorrows);
        if (rateCalculationResultCode != 0) {
            return failOpaque(FailureInfo.WITHDRAW_NEW_SUPPLY_RATE_CALCULATION_FAILED, rateCalculationResultCode);
        }

        // We calculate the newBorrowIndex
        (err, localResults.newBorrowIndex) = calculateInterestIndex(market.borrowIndex, market.borrowRateMantissa, market.blockNumber, getBlockNumber());
        if (err != Error.NO_ERROR) {
            return fail(err, FailureInfo.WITHDRAW_NEW_BORROW_INDEX_CALCULATION_FAILED);
        }

        (rateCalculationResultCode, localResults.newBorrowRateMantissa) = market.interestRateModel.getBorrowRate(asset, localResults.updatedCash, market.totalBorrows);
        if (rateCalculationResultCode != 0) {
            return failOpaque(FailureInfo.WITHDRAW_NEW_BORROW_RATE_CALCULATION_FAILED, rateCalculationResultCode);
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        // We ERC-20 transfer the asset into the protocol (note: pre-conditions already checked above)
        err = doTransferOut(asset, msg.sender, localResults.withdrawAmount);
        if (err != Error.NO_ERROR) {
            // This is safe since it's our first interaction and it didn't do anything if it failed
            return fail(err, FailureInfo.WITHDRAW_TRANSFER_OUT_FAILED);
        }

        // Save market updates
        market.blockNumber = getBlockNumber();
        market.totalSupply =  localResults.newTotalSupply;
        market.supplyRateMantissa = localResults.newSupplyRateMantissa;
        market.supplyIndex = localResults.newSupplyIndex;
        market.borrowRateMantissa = localResults.newBorrowRateMantissa;
        market.borrowIndex = localResults.newBorrowIndex;

        // Save user updates
        localResults.startingBalance = supplyBalance.principal;
        supplyBalance.principal = localResults.userSupplyUpdated;
        supplyBalance.interestIndex = localResults.newSupplyIndex;

        return uint(Error.NO_ERROR); // success
    }

    // logic for borrowing ...

    // logic for repaying loans ...

    // logic for liquidations ...

}