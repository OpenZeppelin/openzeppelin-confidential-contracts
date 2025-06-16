import { ACCOUNT_NAMES } from './constants';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import { ethers } from 'hardhat';

export type AccountNames = (typeof ACCOUNT_NAMES)[number];

export interface Signers {
  [K in AccountNames]: HardhatEthersSigner;
}

const signers: Signers = {} as Signers;

export const initSigners = async (): Promise<void> => {
  if (Object.entries(signers).length === 0) {
    const eSigners = await ethers.getSigners();
    for (let index = 0; index < ACCOUNT_NAMES.length; index++) {
      const name = ACCOUNT_NAMES[index];
      signers[name] = eSigners[index];
    }
  }
};

export const getSigners = async (): Promise<Signers> => {
  return signers;
};
