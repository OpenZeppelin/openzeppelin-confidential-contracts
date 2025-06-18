import { task } from 'hardhat/config';

task('coverage').setAction(async (taskArgs, hre, runSuper) => {
  hre.config.networks.hardhat.allowUnlimitedContractSize = true;
  hre.config.networks.hardhat.blockGasLimit = 1_000_000_000;
  await runSuper(taskArgs);
});
