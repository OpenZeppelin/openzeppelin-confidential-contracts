import { AddressLike, Signer, ethers } from 'ethers';
import { fhevm } from 'hardhat';

const PERMIT_DURATION_SECONDS = 365 * 24 * 60 * 60;

/**
 * Decrypts a handle as `delegate`, using a decryption delegation granted by `delegator`.
 *
 * `contractAddress` is the user-decryption context. It must already be allowed on the handle, and it
 * must differ from `delegator`.
 */
export async function delegatedUserDecryptEuint(
  handle: string,
  contractAddress: AddressLike,
  delegator: AddressLike,
  delegate: Signer,
): Promise<bigint> {
  const [resolvedContractAddress, delegatorAddress, signerAddress, transportKeyPair] = await Promise.all([
    ethers.resolveAddress(contractAddress),
    ethers.resolveAddress(delegator),
    delegate.getAddress(),
    fhevm.client.generateTransportKeyPair(),
  ]);

  const signedPermit = await fhevm.client.signLegacyDecryptionPermit({
    contractAddresses: [resolvedContractAddress],
    delegatorAddress,
    startTimestamp: Math.floor(Date.now() / 1000),
    durationSeconds: PERMIT_DURATION_SECONDS,
    signerAddress,
    signer: delegate,
    transportKeyPair,
  });

  const [decrypted] = await fhevm.client.decryptValues({
    encryptedValues: [handle],
    contractAddress: resolvedContractAddress,
    transportKeyPair,
    signedPermit,
  });

  if (decrypted === undefined || typeof decrypted.value !== 'bigint') {
    throw new Error(`Unexpected decrypted value for handle ${handle}`);
  }
  return decrypted.value;
}
