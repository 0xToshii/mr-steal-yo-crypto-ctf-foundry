// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


contract Multicall {
    /**
     * @dev Receives and executes a batch of function calls on this contract.
     */
    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            results[i] = Address.functionDelegateCall(address(this), data[i]);
        }
        return results;
    }
}

/// @dev Implements dutch auction where payment currency is ETH
contract DutchAuction is Multicall, ReentrancyGuard {

    using SafeERC20 for IERC20;

    /// @dev The multiplier for decimal precision
    uint256 private constant PRECISION = 1e18;

    /// @notice Main market variables.
    struct MarketInfo {
        uint256 startTime;
        uint256 endTime;
        uint256 totalTokens;
    }
    MarketInfo public marketInfo;

    /// @notice Market price variables.
    struct MarketPrice {
        uint256 startPrice;
        uint256 minimumPrice;
    }
    MarketPrice public marketPrice;

    /// @notice Market dynamic variables.
    struct MarketStatus {
        uint256 commitmentsTotal;
        bool finalized;
    }
    MarketStatus public marketStatus;

    /// @notice Address which controls auction, cannot be changed
    address admin;
    /// @notice The token being sold.
    address public auctionToken; 
    /// @notice Where the auction funds will get paid.
    address payable public wallet;  

    /// @notice The commited amount of accounts.
    mapping(address => uint256) public commitments; 
    /// @notice Amount of tokens to claim per address.
    mapping(address => uint256) public claimed;

    /// @notice Event for adding a commitment.
    event AddedCommitment(address addr, uint256 commitment);   
    /// @notice Event for finalization of the auction.
    event AuctionFinalized();
    /// @notice Event for cancellation of the auction.
    event AuctionCancelled();

    constructor() {
        admin = msg.sender;
    }

    /**
     * @notice Initializes main contract variables and transfers funds for the auction.
     * @dev Init function. Payment currency is always ETH.
     * @param _funder The address that funds the token for crowdsale.
     * @param _token Address of the token being sold.
     * @param _totalTokens The total number of tokens to sell in auction.
     * @param _startTime Auction start time.
     * @param _endTime Auction end time.
     * @param _startPrice Starting price of the auction.
     * @param _minimumPrice The minimum auction price.
     * @param _wallet Address where collected funds will be forwarded to.
     */
    function initAuction(
        address _funder,
        address _token, // decimals must be 18
        uint256 _totalTokens,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _startPrice,
        uint256 _minimumPrice,
        address payable _wallet
    ) external {
        require(msg.sender == admin,'invalid caller');
        require(wallet == address(0),'re-init'); // prevents admin from re-init

        require(_startTime >= block.timestamp, "DutchAuction: start time is before current time");
        require(_endTime > _startTime, "DutchAuction: end time must be older than start price");
        require(_totalTokens > 0,"DutchAuction: total tokens must be greater than zero");
        require(_startPrice > _minimumPrice, "DutchAuction: start price must be higher than minimum price");
        require(_minimumPrice > 0, "DutchAuction: minimum price must be greater than 0"); 
        require(_wallet != address(0), "DutchAuction: wallet is the zero address");

        marketInfo.startTime = _startTime;
        marketInfo.endTime = _endTime;
        marketInfo.totalTokens = _totalTokens;

        marketPrice.startPrice = _startPrice;
        marketPrice.minimumPrice = _minimumPrice;

        auctionToken = _token;
        wallet = _wallet;

        IERC20(_token).safeTransferFrom(_funder,address(this),_totalTokens);
    }

    /**
     * @notice Calculates the average price of each token from all commitments.
     * @dev This is each 1e18 of tokens (hence why decimals must be 18 for token)
     * @return Average token price.
     */
    function tokenPrice() public view returns (uint256) {
        return (marketStatus.commitmentsTotal * PRECISION * 1e18)
            / marketInfo.totalTokens / PRECISION;
    }

    /**
     * @notice Returns auction price at any time.
     * @return Fixed start price or minimum price if outside of auction time, otherwise calculated current price.
     */
    function priceFunction() public view returns (uint256) {
        /// @dev Return Auction Price
        if (block.timestamp <= marketInfo.startTime) {
            return marketPrice.startPrice;
        }
        if (block.timestamp >= marketInfo.endTime) {
            return marketPrice.minimumPrice;
        }
        return _currentPrice();
    }

    /**
     * @notice The current clearing price of the Dutch auction.
     * @return The bigger of tokenPrice and priceFunction.
     */
    function clearingPrice() public view returns (uint256) {
        /// @dev If auction successful, return tokenPrice
        if (tokenPrice() > priceFunction()) {
            return tokenPrice();
        }
        return priceFunction();
    }


    ///--------------------------------------------------------
    /// Commit to buying tokens!
    ///--------------------------------------------------------


    /**
     * @notice Checks the amount of ETH to commit and adds the commitment. Refunds the buyer if commit is too high.
     * @param _beneficiary Auction participant ETH address.
     */
    function commitEth(address payable _beneficiary) public payable nonReentrant
    {
        // Get ETH able to be committed
        uint256 ethToTransfer = calculateCommitment(msg.value);

        /// @notice Accept ETH Payments.
        uint256 ethToRefund = msg.value - ethToTransfer;
        if (ethToTransfer > 0) {
            _addCommitment(_beneficiary, ethToTransfer);
        }
        /// @notice Return any ETH to be refunded.
        if (ethToRefund > 0) {
            _beneficiary.transfer(ethToRefund);
        }
    }

    /**
     * @notice Calculates the pricedrop factor.
     * @dev Calculates the drop in price per second
     * @return Value calculated from auction start and end price difference divided the auction duration.
     */
    function priceDrop() public view returns (uint256) {
        MarketInfo memory _marketInfo = marketInfo;
        MarketPrice memory _marketPrice = marketPrice;

        uint256 numerator = _marketPrice.startPrice - _marketPrice.minimumPrice;
        uint256 denominator = _marketInfo.endTime - _marketInfo.startTime;
        return numerator / denominator;
    }

   /**
     * @notice How many tokens the user is able to claim.
     * @param _user Auction participant address.
     * @return claimerCommitment User commitments reduced by already claimed tokens.
     */
    function tokensClaimable(address _user) public view returns (uint256 claimerCommitment) {
        if (commitments[_user] == 0) return 0;
        uint256 unclaimedTokens = IERC20(auctionToken).balanceOf(address(this));

        claimerCommitment = (commitments[_user] * marketInfo.totalTokens) / marketStatus.commitmentsTotal;
        claimerCommitment = claimerCommitment - claimed[_user];

        if (claimerCommitment > unclaimedTokens) {
            claimerCommitment = unclaimedTokens;
        }
    }

    /**
     * @notice Calculates the amout able to be committed during an auction.
     * @param _commitment Commitment user would like to make.
     * @return committed Amount allowed to commit.
     */
    function calculateCommitment(uint256 _commitment) public view returns (uint256 committed) {
        uint256 maxCommitment = (marketInfo.totalTokens * clearingPrice()) / 1e18;
        if ((marketStatus.commitmentsTotal + _commitment) > maxCommitment) {
            return (maxCommitment - marketStatus.commitmentsTotal);
        }
        return _commitment;
    }

    /**
     * @notice Successful if tokens sold equals totalTokens.
     * @return True if tokenPrice is bigger or equal clearingPrice.
     */
    function auctionSuccessful() public view returns (bool) {
        return tokenPrice() >= clearingPrice();
    }

    /**
     * @notice Checks if the auction has ended.
     * @return True if auction is successful or time has ended.
     */
    function auctionEnded() public view returns (bool) {
        return auctionSuccessful() || block.timestamp > marketInfo.endTime;
    }

    /**
     * @return Returns true if market has been finalized
     */
    function finalized() public view returns (bool) {
        return marketStatus.finalized;
    }

    /**
     * @return Returns true if 14 days have passed since the end of the auction
     */
    function finalizeTimeExpired() public view returns (bool) {
        return marketInfo.endTime + 7 days < block.timestamp;
    }

    /**
     * @notice Calculates price during the auction.
     * @return Current auction price.
     */
    function _currentPrice() private view returns (uint256) {
        uint256 priceDiff = (block.timestamp - marketInfo.startTime) * priceDrop();
        return (marketPrice.startPrice - priceDiff);
    }

    /**
     * @notice Updates commitment for this address and total commitment of the auction.
     * @param _addr Bidders address.
     * @param _commitment The amount to commit.
     */
    function _addCommitment(address _addr, uint256 _commitment) internal {
        require(
            block.timestamp >= marketInfo.startTime && 
            block.timestamp <= marketInfo.endTime, 
            "DutchAuction: outside auction hours"
        );
        MarketStatus storage status = marketStatus;
        
        uint256 newCommitment = commitments[_addr] + _commitment;
        
        commitments[_addr] = newCommitment;
        status.commitmentsTotal = status.commitmentsTotal + _commitment;
        emit AddedCommitment(_addr, _commitment);
    }


    //--------------------------------------------------------
    // Finalize Auction
    //--------------------------------------------------------


    /**
     * @notice Cancel Auction
     * @dev Admin can cancel the auction before it starts
     */
    function cancelAuction() public nonReentrant  
    {
        require(hasAdminRole(msg.sender));
        MarketStatus storage status = marketStatus;
        require(!status.finalized, "DutchAuction: auction already finalized");
        require(status.commitmentsTotal == 0, "DutchAuction: auction already committed");
        IERC20(auctionToken).safeTransfer(wallet,marketInfo.totalTokens);
        status.finalized = true;
        emit AuctionCancelled();
    }

    /**
     * @notice Auction finishes successfully above the reserve.
     * @dev Transfer contract funds to initialized wallet.
     */
    function finalize() public nonReentrant  
    {
        require(hasAdminRole(msg.sender) 
                || wallet == msg.sender
                || finalizeTimeExpired(), "DutchAuction: sender must be an admin");
        MarketStatus storage status = marketStatus;

        require(!status.finalized, "DutchAuction: auction already finalized");
        if (auctionSuccessful()) {
            /// @dev Successful auction
            /// @dev Transfer contributed tokens to wallet.
            (bool success,) = wallet.call{value:status.commitmentsTotal}('');
            require(success, 'ETH_TRANSFER_FAILED');
        } else {
            /// @dev Failed auction
            /// @dev Return auction tokens back to wallet.
            require(block.timestamp > marketInfo.endTime, "DutchAuction: auction has not finished yet"); 
            IERC20(auctionToken).safeTransfer(wallet,marketInfo.totalTokens);
        }
        status.finalized = true;
        emit AuctionFinalized();
    }

    /// @notice Withdraws bought tokens, or returns commitment if the sale is unsuccessful.
    function withdrawTokens() public  {
        withdrawTokens(msg.sender);
    }

   /**
     * @notice Withdraws bought tokens, or returns commitment if the sale is unsuccessful.
     * @dev Withdraw tokens only after auction ends.
     * @param beneficiary Whose tokens will be withdrawn.
     */
    function withdrawTokens(address beneficiary) public nonReentrant {
        if (auctionSuccessful()) {
            require(marketStatus.finalized, "DutchAuction: not finalized");
            /// @dev Successful auction! Transfer claimed tokens.
            uint256 tokensToClaim = tokensClaimable(beneficiary);
            require(tokensToClaim > 0, "DutchAuction: No tokens to claim"); 
            claimed[beneficiary] = claimed[beneficiary]+tokensToClaim;
            IERC20(auctionToken).safeTransfer(beneficiary,tokensToClaim);
        } else {
            /// @dev Auction did not meet reserve price.
            /// @dev Return committed funds back to user.
            require(block.timestamp > marketInfo.endTime, "DutchAuction: auction has not finished yet");
            uint256 fundsCommitted = commitments[beneficiary];
            commitments[beneficiary] = 0; // Stop multiple withdrawals and free some gas

            (bool success,) = payable(beneficiary).call{value:fundsCommitted}('');
            require(success, 'ETH_TRANSFER_FAILED');
        }
    }

    /// @notice Returns whether `user` address is admin
    function hasAdminRole(address user) internal returns (bool) {
        return user == admin;
    }

}