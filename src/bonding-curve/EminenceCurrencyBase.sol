// SPDX-License-Identifier: MIT
pragma solidity ^0.5.17;

import "./EminenceCurrencyHelpers.sol";


/// @dev primary currency contract handling bonding of DAI <-> EMN
contract EminenceCurrencyBase is ContinuousToken, ERC20Detailed {

    mapping(address => bool) public gamemasters;
    mapping(address => bool) public npcs;
    
    event AddGM(address indexed newGM, address indexed gm);
    event RevokeGM(address indexed newGM, address indexed gm);
    event AddNPC(address indexed newNPC, address indexed gm);
    event RevokeNPC(address indexed newNPC, address indexed gm);
    event CashShopBuy(address _from, uint  _amount, uint _deposit);
    event CashShopSell(address _from, uint  _amount, uint _reimbursement);
    
    IERC20 public DAI;
    
    constructor (
        string memory name, 
        string memory symbol, 
        uint32 _reserveRatio,
        address daiAddress
    ) public ERC20Detailed(name, symbol, 18) {
        gamemasters[msg.sender] = true;
        reserveRatio = _reserveRatio;
        DAI = IERC20(daiAddress);
        _mint(msg.sender, 1*scale);
    }

    function addNPC(address _npc) external {
        require(gamemasters[msg.sender], "!gm");
        npcs[_npc] = true;
        emit AddNPC(_npc, msg.sender);
    }

    function revokeNPC(address _npc) external {
        require(gamemasters[msg.sender], "!gm");
        npcs[_npc] = false;
        emit RevokeNPC(_npc, msg.sender);
    }

    function addGM(address _gm) external {
        require(gamemasters[msg.sender]||gamemasters[tx.origin], "!gm");
        gamemasters[_gm] = true;
        emit AddGM(_gm, msg.sender);
    }

    function revokeGM(address _gm) external {
        require(gamemasters[msg.sender], "!gm");
        gamemasters[_gm] = false;
        emit RevokeGM(_gm, msg.sender);
    }

    function award(address _to, uint _amount) external {
        require(gamemasters[msg.sender], "!gm");
        _mint(_to, _amount);
    }

    function claim(address _from, uint _amount) external {
        require(gamemasters[msg.sender]||npcs[msg.sender], "!gm");
        _burn(_from, _amount);
    }

    function buy(uint _amount, uint _min) external returns (uint _bought) {
        _bought = _buy(_amount);
        require(_bought >= _min, "slippage");
        DAI.transferFrom(msg.sender, address(this), _amount);
        _mint(msg.sender, _bought);
        emit CashShopBuy(msg.sender, _bought, _amount);
    }

    function sell(uint _amount, uint _min) external returns (uint _bought) {
        _bought = _sell(_amount);
        require(_bought >= _min, "slippage");
        _burn(msg.sender, _amount);
        DAI.transfer(msg.sender, _bought);
        emit CashShopSell(msg.sender, _amount, _bought);
    }

}