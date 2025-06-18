import { ACL_ADDRESS, GATEWAY_URL, KMSVERIFIER_ADDRESS } from './constants';
import { createEncryptedInputMocked, reencryptRequestMocked } from './fhevmjsMocked';
import { createEIP712, createInstance as createFhevmInstance, generateKeypair } from 'fhevmjs';
import { FhevmInstance } from 'fhevmjs/node';
import { network } from 'hardhat';

const kmsAdd = KMSVERIFIER_ADDRESS;
const aclAdd = ACL_ADDRESS;

export const createInstance = async (): Promise<FhevmInstance> => {
  if (network.name === 'hardhat') {
    const instance = {
      reencrypt: reencryptRequestMocked,
      createEncryptedInput: createEncryptedInputMocked,
      getPublicKey: () => '0xFFAA44433',
      generateKeypair: generateKeypair,
      createEIP712: createEIP712(network.config.chainId),
    };
    return instance;
  } else {
    const instance = await createFhevmInstance({
      kmsContractAddress: kmsAdd,
      aclContractAddress: aclAdd,
      networkUrl: network.config.url,
      gatewayUrl: GATEWAY_URL,
    });
    return instance;
  }
};
