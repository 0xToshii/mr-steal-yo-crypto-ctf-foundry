//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";


/// @dev ERC1155 token representation for storing all game assets
/// @dev differs from base ERC1155 contract in that each user can only store
/// @dev a single unique NFT id per token ID, & transfers can only be made to
/// @dev users who do not already own an instance of that token ID
/// @dev NFT id is stored to allow for easy wrapping/unwrapping of assets
contract AssetHolder is Context, ERC165, IERC1155, IERC1155MetadataURI {

    using Address for address;

    // mapping from token ID to account NFT id owned
    // user can only own a single NFT id per token ID
    mapping(uint256 => mapping(address => uint256)) private _idOwned;

    // mapping of whether account owns an NFT id for a token ID
    mapping(uint256 => mapping(address => bool)) private _ownsAny;

    // mapping from account to operator approvals
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    // used as the URI for all token types by relying on ID substitution
    string private _uri;

    /// @dev set URI on initialization
    constructor(string memory uri_) {
        _setURI(uri_);
    }

    /// @dev See {IERC165-supportsInterface}
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IERC1155).interfaceId ||
            interfaceId == type(IERC1155MetadataURI).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @dev returns the same URI for *all* token types
    function uri(uint256) public view virtual override returns (string memory) {
        return _uri;
    }

    /// @dev returns the NFT id for a given user `owner` and token ID `id`
    function getIdOwned(uint256 id, address owner) public view returns (uint256) {
        return _idOwned[id][owner];
    }

    /// @dev returns balance of account for token ID
    /// @dev balance for a token ID can only be 0 or 1
    function balanceOf(address account, uint256 id) public view virtual override returns (uint256) {
        require(account != address(0), "ERC1155: address zero is not a valid owner");
        return _ownsAny[id][account] == true ? 1 : 0;
    }

    /// @dev returns balance of accounts for given token IDs
    function balanceOfBatch(address[] memory accounts, uint256[] memory ids)
        public
        view
        virtual
        override
        returns (uint256[] memory)
    {
        require(accounts.length == ids.length, "ERC1155: accounts and ids length mismatch");

        uint256[] memory batchBalances = new uint256[](accounts.length);

        for (uint256 i = 0; i < accounts.length; ++i) {
            batchBalances[i] = balanceOf(accounts[i], ids[i]);
        }

        return batchBalances;
    }

    /// @dev set approval for all
    function setApprovalForAll(address operator, bool approved) public virtual override {
        _setApprovalForAll(_msgSender(), operator, approved);
    }

    /// @dev return whether `operator` is approved for `account`
    function isApprovedForAll(address account, address operator) public view virtual override returns (bool) {
        return _operatorApprovals[account][operator];
    }
 
    /// @dev single transfer of an NFT id for a specific token ID
    /// @dev `amount` must be 1, `data` is the NFT id to transfer
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public virtual override {
        require(
            from == _msgSender() || isApprovedForAll(from, _msgSender()),
            "ERC1155: caller is not token owner nor approved"
        );
        _safeTransferFrom(from, to, id, amount, data);
    }
    
    /// @dev batch transfer of a set of NFT ids for a set of token IDs
    /// @dev `amounts` must be 1s, `data` is array of NFT ids to transfer
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public virtual override {
        require(
            from == _msgSender() || isApprovedForAll(from, _msgSender()),
            "ERC1155: caller is not token owner nor approved"
        );
        _safeBatchTransferFrom(from, to, ids, amounts, data);
    }

    /// @dev transfers single NFT id from `from` to `to` for a select token type `id`
    /// @dev transfers only allowed to accounts which don't already own same token type `id`
    function _safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) internal virtual {
        require(to != address(0), "ERC1155: transfer to the zero address");
        require(amount == 1, "ERC1155: invalid transfer amount"); // ignored

        address operator = _msgSender();
        uint256[] memory ids = _asSingletonArray(id);
        uint256[] memory amounts = _asSingletonArray(amount);

        _beforeTokenTransfer(operator, from, to, ids, amounts, data);

        uint256 nftId = abi.decode(data,(uint256));

        require(_ownsAny[id][from], "ERC1155: user doesn't own token ID");
        require(_idOwned[id][from] == nftId, "ERC1155: user doesn't own NFT id");
        require(!_ownsAny[id][to], "ERC1155: receiver already has token");

        _ownsAny[id][from] = false;
        _ownsAny[id][to] = true;
        _idOwned[id][to] = nftId;

        emit TransferSingle(operator, from, to, id, amount);

        _afterTokenTransfer(operator, from, to, ids, amounts, data);

        _doSafeTransferAcceptanceCheck(operator, from, to, id, amount, data);
    }

    /// @dev transfers batch of NFT ids from `from` to `to` for set of token type `ids`
    /// @dev transfers only allowed to accounts which don't already own same token types `ids`
    function _safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual {
        require(ids.length == amounts.length, "ERC1155: ids and amounts length mismatch");
        require(to != address(0), "ERC1155: transfer to the zero address");

        address operator = _msgSender();

        _beforeTokenTransfer(operator, from, to, ids, amounts, data);

        uint256[] memory nftIds = abi.decode(data,(uint256[]));

        for (uint256 i = 0; i < ids.length; ++i) {
            uint256 id = ids[i];
            uint256 nftId = nftIds[i];

            require(amounts[i] == 1, "ERC1155: invalid transfer amount"); // ignored

            require(_ownsAny[id][from], "ERC1155: user doesn't own token ID");
            require(_idOwned[id][from] == nftId, "ERC1155: user doesn't own NFT id");
            require(!_ownsAny[id][to], "ERC1155: receiver already has token");

            _ownsAny[id][from] = false;
            _ownsAny[id][to] = true;
            _idOwned[id][to] = nftId;          
        }

        emit TransferBatch(operator, from, to, ids, amounts);

        _afterTokenTransfer(operator, from, to, ids, amounts, data);

        _doSafeBatchTransferAcceptanceCheck(operator, from, to, ids, amounts, data);
    }

    /// @dev sets new URI for all token types
    function _setURI(string memory newuri) internal virtual {
        _uri = newuri;
    }

    /// @dev mints NFT id to `to` for token type `id`
    /// @param data Stores NFT id to mint to `to`
    function _mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) internal virtual {
        require(to != address(0), "ERC1155: mint to the zero address");
        require(amount == 1, "ERC1155: invalid transfer amount"); // ignored

        address operator = _msgSender();
        uint256[] memory ids = _asSingletonArray(id);
        uint256[] memory amounts = _asSingletonArray(amount);

        _beforeTokenTransfer(operator, address(0), to, ids, amounts, data);

        uint256 nftId = abi.decode(data,(uint256));

        require(!_ownsAny[id][to], "ERC1155: receiver already has token");

        _ownsAny[id][to] = true;
        _idOwned[id][to] = nftId;

        emit TransferSingle(operator, address(0), to, id, amount);

        _afterTokenTransfer(operator, address(0), to, ids, amounts, data);

        _doSafeTransferAcceptanceCheck(operator, address(0), to, id, amount, data);
    }

    /// @dev mints batch of NFT ids to `to` for token types `ids`
    /// @param data Stores NFT ids to mint to `to`
    function _mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual {
        require(to != address(0), "ERC1155: mint to the zero address");
        require(ids.length == amounts.length, "ERC1155: ids and amounts length mismatch");

        address operator = _msgSender();

        _beforeTokenTransfer(operator, address(0), to, ids, amounts, data);

        uint256[] memory nftIds = abi.decode(data,(uint256[]));

        for (uint256 i = 0; i < ids.length; i++) {
            uint256 id = ids[i];

            require(amounts[i] == 1, "ERC1155: invalid transfer amount"); // ignored
            require(!_ownsAny[id][to], "ERC1155: receiver already has token");

            _ownsAny[id][to] = true;
            _idOwned[id][to] = nftIds[i];
        }

        emit TransferBatch(operator, address(0), to, ids, amounts);

        _afterTokenTransfer(operator, address(0), to, ids, amounts, data);

        _doSafeBatchTransferAcceptanceCheck(operator, address(0), to, ids, amounts, data);
    }

    /// @dev destroys token type `id` from `from`
    function _burn(
        address from,
        uint256 id,
        uint256 amount
    ) internal virtual {
        require(from != address(0), "ERC1155: burn from the zero address");
        require(amount == 1, "ERC1155: invalid transfer amount"); // ignored

        address operator = _msgSender();
        uint256[] memory ids = _asSingletonArray(id);
        uint256[] memory amounts = _asSingletonArray(amount);

        _beforeTokenTransfer(operator, from, address(0), ids, amounts, "");

        require(_ownsAny[id][from], "ERC1155: user does not own token");
        _ownsAny[id][from] = false;

        emit TransferSingle(operator, from, address(0), id, amount);

        _afterTokenTransfer(operator, from, address(0), ids, amounts, "");
    }

    /// @dev destroys token types `ids` from `from`
    function _burnBatch(
        address from,
        uint256[] memory ids,
        uint256[] memory amounts
    ) internal virtual {
        require(from != address(0), "ERC1155: burn from the zero address");
        require(ids.length == amounts.length, "ERC1155: ids and amounts length mismatch");

        address operator = _msgSender();

        _beforeTokenTransfer(operator, from, address(0), ids, amounts, "");

        for (uint256 i = 0; i < ids.length; i++) {
            uint256 id = ids[i];

            require(amounts[i] == 1, "ERC1155: invalid transfer amount"); // ignored
            require(_ownsAny[id][from], "ERC1155: user does not own token");

            _ownsAny[id][from] = false;
        }

        emit TransferBatch(operator, from, address(0), ids, amounts);

        _afterTokenTransfer(operator, from, address(0), ids, amounts, "");
    }

    /// @dev approves `operator` to operate on all of `owner` tokens
    function _setApprovalForAll(
        address owner,
        address operator,
        bool approved
    ) internal virtual {
        require(owner != operator, "ERC1155: setting approval status for self");
        _operatorApprovals[owner][operator] = approved;
        emit ApprovalForAll(owner, operator, approved);
    }

    /// @dev hook that is called before any token transfer
    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual {}

    /// @dev hook that is called after any token transfer
    function _afterTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual {}

    function _doSafeTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) private {
        if (to.isContract()) {
            try IERC1155Receiver(to).onERC1155Received(operator, from, id, amount, data) returns (bytes4 response) {
                if (response != IERC1155Receiver.onERC1155Received.selector) {
                    revert("ERC1155: ERC1155Receiver rejected tokens");
                }
            } catch Error(string memory reason) {
                revert(reason);
            } catch {
                revert("ERC1155: transfer to non ERC1155Receiver implementer");
            }
        }
    }

    function _doSafeBatchTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) private {
        if (to.isContract()) {
            try IERC1155Receiver(to).onERC1155BatchReceived(operator, from, ids, amounts, data) returns (
                bytes4 response
            ) {
                if (response != IERC1155Receiver.onERC1155BatchReceived.selector) {
                    revert("ERC1155: ERC1155Receiver rejected tokens");
                }
            } catch Error(string memory reason) {
                revert(reason);
            } catch {
                revert("ERC1155: transfer to non ERC1155Receiver implementer");
            }
        }
    }

    function _asSingletonArray(uint256 element) private pure returns (uint256[] memory) {
        uint256[] memory array = new uint256[](1);
        array[0] = element;

        return array;
    }

}