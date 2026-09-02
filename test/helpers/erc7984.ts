import { Addressable, Signer, resolveAddress } from 'ethers';
import { fhevm } from 'hardhat';

/// Largest limit an `euint64` allowance can hold, used when a test does not care about the operator limit.
export const MAX_OPERATOR_LIMIT = 2n ** 64n - 1n;

/// Encrypts `limit` and registers `operator` as an operator of `holder` until `until`.
export async function setOperator(
  token: any,
  holder: Signer,
  operator: string | Addressable,
  until: bigint | number,
  limit: bigint | number = MAX_OPERATOR_LIMIT,
) {
  const input = await fhevm
    .createEncryptedInput(await resolveAddress(token), await holder.getAddress())
    .add64(limit)
    .encrypt();

  return token.connect(holder).setOperator(operator, until, input.handles[0], input.inputProof);
}
