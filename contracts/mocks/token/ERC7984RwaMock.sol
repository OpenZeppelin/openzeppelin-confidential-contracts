// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {FHE, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984Rwa} from "./../../token/ERC7984/extensions/ERC7984Rwa.sol";
import {HandleAccessManager} from "./../../utils/HandleAccessManager.sol";
import {ERC7984Mock} from "./ERC7984Mock.sol";

// solhint-disable func-name-mixedcase
contract ERC7984RwaMock is ERC7984Rwa, ERC7984Mock, HandleAccessManager {
    constructor(
        string memory name,
        string memory symbol,
        string memory tokenUri,
        address admin
    ) ERC7984Rwa(admin) ERC7984Mock(name, symbol, tokenUri) {}

    function _update(
        address from,
        address to,
        euint64 amount
    ) internal virtual override(ERC7984Mock, ERC7984Rwa) returns (euint64) {
        return super._update(from, to, amount);
    }

    function _validateHandleAllowance(bytes32 handle) internal view override onlyAgent {}

    // solhint-disable-next-line func-name-mixedcase
    function $_setConfidentialFrozen(address account, uint64 amount) public virtual {
        _setConfidentialFrozen(account, FHE.asEuint64(amount));
    }
}
