// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984Restricted} from "../../token/ERC7984/extensions/ERC7984Restricted.sol";

abstract contract ERC7984RestrictedMock is ERC7984Restricted, SepoliaConfig {
    function _mint(address to, uint64 amount) internal {
        _mint(to, FHE.asEuint64(amount));
    }

    function _burn(address from, uint64 amount) internal {
        _burn(from, FHE.asEuint64(amount));
    }

    function transfer(address to, uint64 amount) public {
        _transfer(msg.sender, to, FHE.asEuint64(amount));
    }
}
