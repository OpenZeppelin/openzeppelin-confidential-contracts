import { AddressLike, MaxUint256, Signer, resolveAddress, toBeHex } from 'ethers';
import { fhevm } from 'hardhat';

/// Registers `operator` as an operator of `holder` until `until`, encrypting `limit` when one is given.
/// Omitting `limit` sends the `UNLIMITED_OPERATOR` sentinel, which registers an unlimited operator.
/// Limit handle (`~bytes32(0)`) that marks an operator as unlimited.
export const UNLIMITED_OPERATOR = toBeHex(MaxUint256, 32);

export async function setOperator(
  token: any, // ethers.Contract (that implement ERC7984)
  holder: Signer,
  operator: AddressLike,
  until: bigint | number,
  limit?: bigint | number,
) {
  const input = await (limit === undefined
    ? Promise.resolve({ handles: [UNLIMITED_OPERATOR], inputProof: '0x' })
    : Promise.all([resolveAddress(token), holder.getAddress()]).then(([tokenAddress, holderAddress]) =>
        fhevm.createEncryptedInput(tokenAddress, holderAddress).add64(limit).encrypt(),
      ));

  return token.connect(holder).setOperator(operator, until, input.handles[0], input.inputProof);
}
