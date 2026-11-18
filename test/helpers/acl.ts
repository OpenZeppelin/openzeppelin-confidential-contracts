import type { IACL } from '../../types';
import cleartextAclAbi from '@fhevm/host-contracts-cleartext/abi/CleartextACL.json';
import { Addressable, Signer } from 'ethers';
import { ethers, fhevm } from 'hardhat';

export function getAclAddress() {
  const aclAddress = fhevm.client.chain?.fhevm.contracts.acl.address;
  if (aclAddress === undefined) {
    throw new Error('FHEVM client chain is not initialized');
  }
  return aclAddress;
}

export function getAcl() {
  return ethers.getContractAt(cleartextAclAbi, getAclAddress()) as unknown as Promise<IACL>;
}

export async function allowHandle(from: Signer, to: Addressable, handle: string) {
  const acl = (await getAcl()).connect(from);
  await acl.allow(handle, await ethers.resolveAddress(to));
}
