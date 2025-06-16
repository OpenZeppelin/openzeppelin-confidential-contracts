import './hardhat/coverage';
import './hardhat/provider';
import './hardhat/testEnvironment';
import '@nomicfoundation/hardhat-chai-matchers';
import '@nomicfoundation/hardhat-ethers';
import dotenv from 'dotenv';
import 'hardhat-exposed';
import 'hardhat-gas-reporter';
import 'hardhat-ignore-warnings';
import { HardhatUserConfig } from 'hardhat/config';
import 'solidity-coverage';
import 'solidity-docgen';

dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.29',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      evmVersion: 'cancun',
    },
  },
  gasReporter: {
    currency: 'USD',
    enabled: !!process.env.REPORT_GAS,
    excludeContracts: [],
    src: './contracts',
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  typechain: {
    outDir: 'types',
    target: 'ethers-v6',
  },
  docgen: require('./docs/config'),
};

export default config;
