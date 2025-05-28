import { impersonateAccount, setBalance } from "@nomicfoundation/hardhat-network-helpers";
import { Addressable, Signer, ethers } from "ethers";
import fs from "fs";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { ACL_ADDRESS } from "../../hardhat/testEnvironment";

const DEFAULT_BALANCE: bigint = 10000n * ethers.WeiPerEther;

export async function impersonate(hre: HardhatRuntimeEnvironment, account: string, balance: bigint = DEFAULT_BALANCE) {
  return impersonateAccount(account)
    .then(() => setBalance(account, balance))
    .then(() => hre.ethers.getSigner(account));
}

export async function allowHandle(hre: HardhatRuntimeEnvironment, from: Signer, to: Addressable, handle: string) {
  const acl_abi = JSON.parse(
    fs.readFileSync("node_modules/fhevm-core-contracts/artifacts/contracts/ACL.sol/ACL.json", "utf8"),
  ).abi;
  const aclContract = await hre.ethers.getContractAt(acl_abi, ACL_ADDRESS);

  await aclContract.connect(from).allow(handle, to);
}
