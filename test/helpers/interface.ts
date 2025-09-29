import { Interface } from 'ethers';
import { ethers } from 'hardhat';

export function getFunctions(interfaceFactory: any) {
  return (interfaceFactory.createInterface() as Interface).fragments
    .filter(f => f.type == 'function')
    .map(f => f.format());
}

export function getInterfaceId(signatures: string[]) {
  return ethers.toBeHex(
    signatures.reduce((acc, signature) => acc ^ ethers.toBigInt(ethers.FunctionFragment.from(signature).selector), 0n),
    4,
  );
}
