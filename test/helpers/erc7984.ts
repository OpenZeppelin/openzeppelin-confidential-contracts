import { AddressLike, Signer, ZeroHash, resolveAddress } from 'ethers';
import { fhevm } from 'hardhat';

/// Registers `operator` as an operator of `holder` until `until`, encrypting `limit` when one is given.
/// Omitting `limit` sends the empty handle, which registers an unlimited operator.
export async function setOperator(
  token: any, // ethers.Contract (that implement ERC7984)
  holder: Signer,
  operator: AddressLike,
  until: bigint | number,
  limit?: bigint | number,
) {
  const input = await (limit === undefined
    ? Promise.resolve({ handles: [ZeroHash], inputProof: '0x' })
    : Promise.all([resolveAddress(token), holder.getAddress()]).then(([tokenAddress, holderAddress]) =>
        fhevm.createEncryptedInput(tokenAddress, holderAddress).add64(limit).encrypt(),
      ));

  return token.connect(holder).setOperator(operator, until, input.handles[0], input.inputProof);
}
