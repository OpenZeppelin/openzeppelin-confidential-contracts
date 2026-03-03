// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC7984ERC20Wrapper, ERC7984} from "../../token/ERC7984/extensions/ERC7984ERC20Wrapper.sol";
import {ERC7984Mock} from "./ERC7984Mock.sol";
import {euint64} from "@fhevm/solidity/lib/FHE.sol";

contract ERC7984ERC20WrapperMock is ERC7984ERC20Wrapper, ZamaEthereumConfig, ERC7984Mock {
    constructor(
        IERC20 token,
        string memory name,
        string memory symbol,
        string memory uri
    ) ERC7984ERC20Wrapper(token) ERC7984Mock(name, symbol, uri) {}

    function supportsInterface(bytes4 interfaceId) public view override(ERC7984ERC20Wrapper, ERC7984) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function decimals() public view override(ERC7984ERC20Wrapper, ERC7984) returns (uint8) {
        return super.decimals();
    }

    function _update(
        address from,
        address to,
        euint64 amount
    ) internal virtual override(ERC7984ERC20Wrapper, ERC7984Mock) returns (euint64) {
        return super._update(from, to, amount);
    }
}
