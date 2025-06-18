import { awaitCoprocessor, getClearText } from './coprocessorUtils';
import { toBufferBE } from 'bigint-buffer';
import { ethers, network } from 'hardhat';

export const mineNBlocks = async (n: number) => {
  for (let index = 0; index < n; index++) {
    await ethers.provider.send('evm_mine');
  }
};

export const bigIntToBytes64 = (value: bigint) => {
  return new Uint8Array(toBufferBE(value, 64));
};

export const bigIntToBytes128 = (value: bigint) => {
  return new Uint8Array(toBufferBE(value, 128));
};

export const bigIntToBytes256 = (value: bigint) => {
  return new Uint8Array(toBufferBE(value, 256));
};

export const waitNBlocks = async (Nblocks: number) => {
  const currentBlock = await ethers.provider.getBlockNumber();
  if (network.name === 'hardhat') {
    await produceDummyTransactions(Nblocks);
  }
  await waitForBlock(currentBlock + Nblocks);
};

export const produceDummyTransactions = async (blockCount: number) => {
  let counter = blockCount;
  while (counter >= 0) {
    counter--;
    const [signer] = await ethers.getSigners();
    const nullAddress = '0x0000000000000000000000000000000000000000';
    const tx = {
      to: nullAddress,
      value: 0n,
    };
    const receipt = await signer.sendTransaction(tx);
    await receipt.wait();
  }
};

const waitForBlock = (blockNumber: bigint | number) => {
  return new Promise((resolve, reject) => {
    const waitBlock = async (currentBlock: number) => {
      if (blockNumber <= BigInt(currentBlock)) {
        await ethers.provider.off('block', waitBlock);
        resolve(blockNumber);
      }
    };
    ethers.provider.on('block', waitBlock).catch(err => {
      reject(err);
    });
  });
};

const EBOOL_T = 0;
const EUINT4_T = 1;
const EUINT8_T = 2;
const EUINT16_T = 3;
const EUINT32_T = 4;
const EUINT64_T = 5;
const EUINT128_T = 6;
const EUINT160_T = 7; // @dev It is the one for eaddresses.
const EUINT256_T = 8;
const EBYTES64_T = 9;
const EBYTES128_T = 10;
const EBYTES256_T = 11;

function verifyType(handle: bigint, expectedType: number) {
  if (handle === 0n) {
    throw 'Handle is not initialized';
  }
  if (handle.toString(2).length > 256) {
    throw 'Handle is not a bytes32';
  }
  const typeCt = handle >> 8n;
  if (Number(typeCt % 256n) !== expectedType) {
    throw 'Wrong encrypted type for the handle';
  }
}

export const debug = {
  /**
   * @debug
   * This function is intended for debugging purposes only.
   * It cannot be used in production code, since it requires the FHE private key for decryption.
   * In production, decryption is only possible via an asynchronous on-chain call to the Gateway.
   *
   * @param {bigint} a handle to decrypt
   * @returns {bool}
   */
  decryptBool: async (handle: bigint): Promise<boolean> => {
    verifyType(handle, EBOOL_T);
    if (network.name === 'hardhat') {
      await awaitCoprocessor();
      return (await getClearText(handle)) === '1';
    } else {
      throw Error('The debug.decryptBool function can only be called in mocked mode');
    }
  },

  /**
   * @debug
   * This function is intended for debugging purposes only.
   * It cannot be used in production code, since it requires the FHE private key for decryption.
   * In production, decryption is only possible via an asynchronous on-chain call to the Gateway.
   *
   * @param {bigint} handle to decrypt
   * @returns {bigint}
   */
  decrypt4: async (handle: bigint): Promise<bigint> => {
    verifyType(handle, EUINT4_T);
    if (network.name === 'hardhat') {
      await awaitCoprocessor();
      return BigInt(await getClearText(handle));
    } else {
      throw Error('The debug.decrypt4 function can only be called in mocked mode');
    }
  },

  /**
   * @debug
   * This function is intended for debugging purposes only.
   * It cannot be used in production code, since it requires the FHE private key for decryption.
   * In production, decryption is only possible via an asynchronous on-chain call to the Gateway.
   *
   * @param {bigint} a handle to decrypt
   * @returns {bigint}
   */
  decrypt8: async (handle: bigint): Promise<bigint> => {
    verifyType(handle, EUINT8_T);
    if (network.name === 'hardhat') {
      await awaitCoprocessor();
      return BigInt(await getClearText(handle));
    } else {
      throw Error('The debug.decrypt8 function can only be called in mocked mode');
    }
  },

  /**
   * @debug
   * This function is intended for debugging purposes only.
   * It cannot be used in production code, since it requires the FHE private key for decryption.
   * In production, decryption is only possible via an asynchronous on-chain call to the Gateway.
   *
   * @param {bigint} handle to decrypt
   * @returns {bigint}
   */
  decrypt16: async (handle: bigint): Promise<bigint> => {
    verifyType(handle, EUINT16_T);
    if (network.name === 'hardhat') {
      await awaitCoprocessor();
      return BigInt(await getClearText(handle));
    } else {
      throw Error('The debug.decrypt16 function can only be called in mocked mode');
    }
  },

  /**
   * @debug
   * This function is intended for debugging purposes only.
   * It cannot be used in production code, since it requires the FHE private key for decryption.
   * In production, decryption is only possible via an asynchronous on-chain call to the Gateway.
   *
   * @param {bigint} handle to decrypt
   * @returns {bigint}
   */
  decrypt32: async (handle: bigint): Promise<bigint> => {
    verifyType(handle, EUINT32_T);
    if (network.name === 'hardhat') {
      await awaitCoprocessor();
      return BigInt(await getClearText(handle));
    } else {
      throw Error('The debug.decrypt32 function can only be called in mocked mode');
    }
  },

  /**
   * @debug
   * This function is intended for debugging purposes only.
   * It cannot be used in production code, since it requires the FHE private key for decryption.
   * In production, decryption is only possible via an asynchronous on-chain call to the Gateway.
   *
   * @param {bigint} handle to decrypt
   * @returns {bigint}
   */
  decrypt64: async (handle: bigint): Promise<bigint> => {
    verifyType(handle, EUINT64_T);
    if (network.name === 'hardhat') {
      await awaitCoprocessor();
      return BigInt(await getClearText(handle));
    } else {
      throw Error('The debug.decrypt64 function can only be called in mocked mode');
    }
  },

  /**
   * @debug
   * This function is intended for debugging purposes only.
   * It cannot be used in production code, since it requires the FHE private key for decryption.
   * In production, decryption is only possible via an asynchronous on-chain call to the Gateway.
   *
   * @param {bigint} handle to decrypt
   * @returns {bigint}
   */
  decrypt128: async (handle: bigint): Promise<bigint> => {
    verifyType(handle, EUINT128_T);
    if (network.name === 'hardhat') {
      await awaitCoprocessor();
      return BigInt(await getClearText(handle));
    } else {
      throw Error('The debug.decrypt128 function can only be called in mocked mode');
    }
  },

  /**
   * @debug
   * This function is intended for debugging purposes only.
   * It cannot be used in production code, since it requires the FHE private key for decryption.
   * In production, decryption is only possible via an asynchronous on-chain call to the Gateway.
   *
   * @param {bigint} handle to decrypt
   * @returns {bigint}
   */
  decrypt256: async (handle: bigint): Promise<bigint> => {
    verifyType(handle, EUINT256_T);
    if (network.name === 'hardhat') {
      await awaitCoprocessor();
      return BigInt(await getClearText(handle));
    } else {
      throw Error('The debug.decrypt256 function can only be called in mocked mode');
    }
  },

  /**
   * @debug
   * This function is intended for debugging purposes only.
   * It cannot be used in production code, since it requires the FHE private key for decryption.
   * In production, decryption is only possible via an asynchronous on-chain call to the Gateway.
   *
   * @param {bigint} handle to decrypt
   * @returns {string}
   */
  decryptAddress: async (handle: bigint): Promise<string> => {
    verifyType(handle, EUINT160_T);
    if (network.name === 'hardhat') {
      await awaitCoprocessor();
      const bigintAdd = BigInt(await getClearText(handle));
      const handleStr = '0x' + bigintAdd.toString(16).padStart(40, '0');
      return handleStr;
    } else {
      throw Error('The debug.decryptAddress function can only be called in mocked mode');
    }
  },

  /**
   * @debug
   * This function is intended for debugging purposes only.
   * It cannot be used in production code, since it requires the FHE private key for decryption.
   * In production, decryption is only possible via an asynchronous on-chain call to the Gateway.
   *
   * @param {bigint} a handle to decrypt
   * @returns {bigint}
   */
  decryptEbytes64: async (handle: bigint): Promise<string> => {
    verifyType(handle, EBYTES64_T);
    if (network.name === 'hardhat') {
      await awaitCoprocessor();
      return ethers.toBeHex(await getClearText(handle), 64);
    } else {
      throw Error('The debug.decryptEbytes64 function can only be called in mocked mode');
    }
  },

  /**
   * @debug
   * This function is intended for debugging purposes only.
   * It cannot be used in production code, since it requires the FHE private key for decryption.
   * In production, decryption is only possible via an asynchronous on-chain call to the Gateway.
   *
   * @param {bigint} handle to decrypt
   * @returns {bigint}
   */
  decryptEbytes128: async (handle: bigint): Promise<string> => {
    verifyType(handle, EBYTES128_T);
    if (network.name === 'hardhat') {
      await awaitCoprocessor();
      return ethers.toBeHex(await getClearText(handle), 128);
    } else {
      throw Error('The debug.decryptEbytes128 function can only be called in mocked mode');
    }
  },

  /**
   * @debug
   * This function is intended for debugging purposes only.
   * It cannot be used in production code, since it requires the FHE private key for decryption.
   * In production, decryption is only possible via an asynchronous on-chain call to the Gateway.
   *
   * @param {bigint} handle to decrypt
   * @returns {bigint}
   */
  decryptEbytes256: async (handle: bigint): Promise<string> => {
    verifyType(handle, EBYTES256_T);
    if (network.name === 'hardhat') {
      await awaitCoprocessor();
      return ethers.toBeHex(await getClearText(handle), 256);
    } else {
      throw Error('The debug.decryptEbytes256 function can only be called in mocked mode');
    }
  },
};
