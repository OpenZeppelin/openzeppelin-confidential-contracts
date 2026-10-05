import { impersonateAccount, setBalance } from '@nomicfoundation/hardhat-network-helpers';
import { Addressable, Signer, ethers } from 'ethers';
import { fhevm } from 'hardhat';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

const DEFAULT_BALANCE: bigint = 10000n * ethers.WeiPerEther;

export async function impersonate(hre: HardhatRuntimeEnvironment, account: string, balance: bigint = DEFAULT_BALANCE) {
  return impersonateAccount(account)
    .then(() => setBalance(account, balance))
    .then(() => hre.ethers.getSigner(account));
}

export function getAclAddress() {
  const aclAddress = fhevm.client.chain?.fhevm.contracts.acl.address;
  if (aclAddress === undefined) {
    throw new Error('FHEVM client chain is not initialized');
  }
  return aclAddress;
}

export async function allowHandle(hre: HardhatRuntimeEnvironment, from: Signer, to: Addressable, handle: string) {
  const aclContract = await hre.ethers.getContractAt(
    ['function allow(bytes32 handle, address account)'],
    getAclAddress(),
  );

  await aclContract.connect(from).allow(handle, await ethers.resolveAddress(to));
}
