// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, externalEuint64, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {BatcherConfidential} from "./../../utils/BatcherConfidential.sol";
import {ExchangeMock} from "./../finance/ExchangeMock.sol";

abstract contract BatcherConfidentialSwapMock is ZamaEthereumConfig, BatcherConfidential {
    ExchangeMock public exchange;
    address public admin;
    bool public setExchangeRate = true;

    constructor(ExchangeMock exchange_, address admin_) {
        exchange = exchange_;
        admin = admin_;
    }

    function routeDescription() public pure override returns (string memory) {
        return "Exchange fromToken for toToken by swapping through the mock exchange.";
    }

    function shouldSetExchangeRate(bool setExchangeRate_) public {
        setExchangeRate = setExchangeRate_;
    }

    /// @dev Join the current batch with `externalAmount` and `inputProof`.
    function join(externalEuint64 externalAmount, bytes calldata inputProof) public virtual returns (euint64) {
        euint64 amount = FHE.fromExternal(externalAmount, inputProof);
        FHE.allowTransient(amount, address(fromToken()));
        euint64 transferred = fromToken().confidentialTransferFrom(msg.sender, address(this), amount);

        euint64 joinedAmount = _join(msg.sender, transferred);
        euint64 refundAmount = FHE.sub(transferred, joinedAmount);

        FHE.allowTransient(refundAmount, address(fromToken()));

        fromToken().confidentialTransfer(msg.sender, refundAmount);

        return joinedAmount;
    }

    function join(uint64 amount) public {
        euint64 ciphertext = FHE.asEuint64(amount);
        FHE.allowTransient(ciphertext, msg.sender);

        bytes4 selector = bytes4(keccak256("join(bytes32,bytes)"));
        bytes memory callData = abi.encodePacked(
            selector,
            abi.encode(externalEuint64.wrap(euint64.unwrap(ciphertext)), hex"")
        );

        Address.functionDelegateCall(address(this), callData);
    }

    function quit(uint256 batchId) public virtual override returns (euint64) {
        euint64 amount = super.quit(batchId);
        FHE.allow(totalDeposits(currentBatchId()), admin);
        return amount;
    }

    function _join(address to, euint64 amount) internal virtual override returns (euint64) {
        euint64 joinedAmount = super._join(to, amount);
        FHE.allow(totalDeposits(currentBatchId()), admin);
        return joinedAmount;
    }

    function _executeRoute(uint256, uint256 unwrapAmount) internal override returns (bool) {
        // Approve exchange to spend unwrapped tokens
        uint256 rawAmount = unwrapAmount * fromToken().rate();
        IERC20(fromToken().underlying()).approve(address(exchange), rawAmount);

        // Swap unwrapped tokens via exchange
        exchange.swapAToB(rawAmount);

        return setExchangeRate;
    }
}
