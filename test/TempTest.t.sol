// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {FhevmTest} from "forge-fhevm/FhevmTest.sol";
import {ERC7984Mock} from "contracts/mocks/token/ERC7984/ERC7984Mock.sol";
import {FHE, externalEuint64, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {Vm} from "forge-std/Vm.sol";

contract TempTest is FhevmTest {
    ERC7984Mock public token;
    Vm.Wallet public aliceWallet = vm.createWallet("alice");

    function setUp() public override {
        super.setUp();
        token = new ERC7984Mock("Token", "TKN", "URI-HERE");
        token.$_mint(aliceWallet.addr, 1000);
    }

    function test_tempTest() public {
        (externalEuint64 handle, bytes memory proof) = encryptUint64(100, aliceWallet.addr, address(token));

        vm.prank(aliceWallet.addr);
        token.confidentialTransfer(address(this), handle, proof);

        bytes memory sig = signUserDecrypt(aliceWallet.privateKey, address(token));
        assertEq(
            userDecrypt(
                bytes32(euint64.unwrap(token.confidentialBalanceOf(aliceWallet.addr))),
                aliceWallet.addr,
                address(token),
                sig
            ),
            1000 - 100
        );
    }
}
