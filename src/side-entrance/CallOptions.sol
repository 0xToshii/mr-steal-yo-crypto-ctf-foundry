// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


interface IUniswapRouter {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

interface IUniswapFactory {
    function getPair(address, address) external returns (address);
}

interface IUniswapV2Pair {
    function swap(
        uint amount0Out, 
        uint amount1Out, 
        address to, 
        bytes calldata data
    ) external;
    function token0() external returns (address);
    function token1() external returns (address);
    function getReserves() external returns (uint112,uint112,uint32);
}

/// @dev Basic implementation that handles American covered call options for wETH-USDC
/// @dev Flashloan functionality to support executing an option by borrowing from Uniswap
contract CallOptions is ReentrancyGuard {

    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;

    /// @dev Struct representing a single covered call option
    struct Option {
        uint256 ethAmount; // amount of ETH locked up
        uint256 usdcStrike; // strike price of ETH in USDC (full price, not per unit)
        uint256 usdcPremium; // premium to purchase option
        uint256 expiry; // expiration time of option
    }

    Counters.Counter private _optionsId; // incremented for each option created, to create unique ids

    mapping(bytes32 => Option) public optionsData;
    mapping(bytes32 => address) private _optionsOwner; // address which issued option
    mapping(bytes32 => address) private _optionsBuyer; // address which bought option
    bytes32[] public optionIds; // stores all created option ids

    IERC20 usdc;
    IERC20 eth;
    IUniswapV2Pair usdcEthPair; // USDC is token0
    IUniswapFactory factory;
    IUniswapRouter router;

    constructor(
        address _usdc,
        address _eth,
        address _usdcEthPair, // for swaps
        address _factory,
        address _router
    ) {
        usdc = IERC20(_usdc);
        eth = IERC20(_eth);
        usdcEthPair = IUniswapV2Pair(_usdcEthPair);
        factory = IUniswapFactory(_factory);
        router = IUniswapRouter(_router);
    }

    /// @dev Returns the id of the latest added option
    function getLatestOptionId() external view returns (bytes32) {
        return optionIds[optionIds.length-1];
    }

    /// @dev Returns the owner of a given `optionId` option
    function getOwner(bytes32 optionId) external view returns (address) {
        return _optionsOwner[optionId];
    }

    /// @dev Returns the buyer of a given `optionId` option
    function getBuyer(bytes32 optionId) external view returns (address) {
        return _optionsBuyer[optionId];
    }

    /// @dev User can create option with specific parameters
    /// @dev Pulls wETH from user upon creation
    function createOption(
        uint256 _ethAmount,
        uint256 _usdcStrike,
        uint256 _usdcPremium,
        uint128 _expiry
    ) external nonReentrant {
        require(_ethAmount > 0,'ethAmount');
        require(_usdcStrike > 0,'usdcStrike');
        require(_usdcPremium > 0,'usdcPremium');
        require(_expiry > block.timestamp,'expiry');

        Option memory userOption = Option(
            _ethAmount,
            _usdcStrike,
            _usdcPremium,
            _expiry
        );

        eth.safeTransferFrom(msg.sender,address(this),_ethAmount);
        bytes32 optionId = keccak256(abi.encodePacked(msg.sender,_optionsId.current()));
        optionIds.push(optionId);
        _optionsId.increment();

        optionsData[optionId]=userOption;
        _optionsOwner[optionId]=msg.sender;
    }

    /// @dev Allows option owner to remove the `optionId` option when in valid state
    /// @dev Valid states: option hasn't been bought || not been executed & expiry passed
    function removeOption(bytes32 optionId) external nonReentrant {
        require(_optionsOwner[optionId] == msg.sender,'invalid owner/option');

        Option memory userOption = optionsData[optionId];
        require(
            _optionsBuyer[optionId] == address(0) || // not bought
            block.timestamp > userOption.expiry, // expiry passed
            'option not removable'
        );

        _optionsOwner[optionId] = address(0); // option no longer valid
        eth.safeTransfer(msg.sender,userOption.ethAmount);
    }

    /// @dev User purchases `optionId` option
    function purchaseOption(bytes32 optionId) external nonReentrant {
        address optionOwner = _optionsOwner[optionId];
        require(optionOwner != address(0),'invalid option');
        require(_optionsBuyer[optionId] == address(0),'option already bought');

        // sends premium directly to option owner
        usdc.safeTransferFrom(msg.sender,optionOwner,optionsData[optionId].usdcPremium);
        _optionsBuyer[optionId]=msg.sender;
    }

    /// @dev Allows buyer of `optionId` option to execute it
    /// @dev Execution involves sending strikePrice in USDC and receiving ethAmount in ETH
    function executeOption(bytes32 optionId) external nonReentrant {
        (uint256 ethAmount,uint256 usdcStrike,address optionOwner) = _executeOptionLogic(optionId, msg.sender);
        usdc.safeTransferFrom(msg.sender,optionOwner,usdcStrike);
        eth.safeTransfer(msg.sender,ethAmount);
    }

    /// @dev Executes an option using a Uniswap flashloan from `_pair` pool
    /// @dev User must have already paid the premium for the option
    /// @dev Automatically swaps ETH through Uniswap pool to pay off loan
    function executeOptionFlashloan(bytes32 optionId, address _pair) external nonReentrant {
        require(_optionsOwner[optionId] != address(0),'not valid option');
        require(_optionsBuyer[optionId] == msg.sender,'not option buyer');

        uint256 borrowAmount = optionsData[optionId].usdcStrike; // loan amount required
        uint256 interestAmount = borrowAmount * 1000 * 1e18 / 997 / 1e18 + 1; // loan payment

        bytes memory data = abi.encode(optionId,msg.sender,interestAmount);

        IUniswapV2Pair pair = IUniswapV2Pair(_pair);
        address token0 = pair.token0();
        address token1 = pair.token1();

        require(token0 == address(usdc) || token1 == address(usdc), 'invalid pair');

        uint256 amount0Out = token0 == address(usdc) ? borrowAmount : 0;
        uint256 amount1Out = token0 == address(usdc) ? 0 : borrowAmount;

        pair.swap(amount0Out, amount1Out, address(this), data); // init flashloan
    }

    /// @dev Uniswap callback
    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external {
        IUniswapV2Pair pair = IUniswapV2Pair(msg.sender);

        address token0 = pair.token0();
        address token1 = pair.token1();
        require(msg.sender == factory.getPair(token0, token1),'invalid callback');

        (bytes32 optionId, address to, uint256 interestAmount) = abi.decode(data, (bytes32, address, uint256));

        (uint256 gainedEth,uint256 usdcStrike,address optionOwner) = _executeOptionLogic(optionId,to);
        usdc.safeTransfer(optionOwner,usdcStrike); // flashloaned USDC sent to this address, not `to`

        (uint112 reserve0, uint112 reserve1,) = usdcEthPair.getReserves();
        uint256 minOut = gainedEth*uint256(reserve0)*99*1e18/uint256(reserve1)/100/1e18; // 1% slippage
        
        address[] memory path = new address[](2);
        path[0]=address(eth);
        path[1]=address(usdc);

        eth.approve(address(router),gainedEth); // exact approval
        router.swapExactTokensForTokens(
            gainedEth,
            minOut,
            path,
            to, // send all swapped funds to the user
            block.timestamp*2
        );

        usdc.safeTransferFrom(to,msg.sender,interestAmount); // pay back the flashloan
    }

    /// @dev Handles the transfer of funds when an option is executed
    /// @dev Handles both the base case & when flashloans are used
    function _executeOptionLogic(
        bytes32 optionId,
        address to
    ) internal returns (uint256,uint256,address) {
        address optionOwner = _optionsOwner[optionId];
        require(optionOwner != address(0),'not valid option');
        require(_optionsBuyer[optionId] == to,'not option buyer');

        Option memory userOption = optionsData[optionId];
        require(block.timestamp <= userOption.expiry,'option expiry has passed');

        _optionsOwner[optionId] = address(0); // option no longer valid
        return (userOption.ethAmount,userOption.usdcStrike,optionOwner);
    }

}