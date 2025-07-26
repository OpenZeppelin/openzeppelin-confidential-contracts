// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {ConfidentialFungibleTokenERC20Events} from "./../token/extensions/ConfidentialFungibleTokenERC20Events.sol";

// solhint-disable func-name-mixedcase
abstract contract ConfidentialFungibleTokenERC20EventsMock is ConfidentialFungibleTokenERC20Events, SepoliaConfig {
    function $_mint(
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public returns (euint64 transferred) {
        return _mint(to, FHE.fromExternal(encryptedAmount, inputProof));
    }
}
