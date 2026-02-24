import { $ERC7984RwaModularCompliance } from '../../../types/contracts-exposed/token/ERC7984/extensions/ERC7984RwaModularCompliance.sol/$ERC7984RwaModularCompliance';
import { FhevmType } from '@fhevm/hardhat-plugin';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

enum ModuleType {
  Standard,
  ForceTransfer,
}

describe('BalanceCapComplianceModuleConfidential', function () {
  beforeEach(async function () {
    const [anyone, admin, agent1, holder, recipient] = await ethers.getSigners();
    const token = (await ethers.deployContract('$ERC7984RwaModularComplianceMock', [
      'name',
      'symbol',
      'uri',
      admin,
    ])) as unknown as $ERC7984RwaModularCompliance;
    await token.connect(admin).addAgent(agent1);
    const complianceModule = await ethers.deployContract('$BalanceCapComplianceModuleConfidentialMock');

    await token
      .connect(admin)
      .installModule(
        ModuleType.Standard,
        complianceModule,
        ethers.AbiCoder.defaultAbiCoder().encode(['uint64'], [10_000]),
      );

    // await token['$_mint(address,uint64)'](holder, 8000n.toString());
    // await token['$_mint(address,uint64)'](anyone, 8000n.toString());

    Object.assign(this, {
      token,
      complianceModule,
      admin,
      agent1,
      recipient,
      holder,
      anyone,
    });
  });

  describe.only('_isCompliantTransfer', function () {
    it('should allow transfer if new balance is less than max balance', async function () {
      const beforeBalance = await this.token.confidentialBalanceOf(this.recipient);
      const tx = await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 1000n);
      //   const afterBalance = await this.token.confidentialBalanceOf(this.recipient);

      //   expect(beforeBalance).to.equal(0n);
      //   await expect(
      //     fhevm.userDecryptEuint(FhevmType.euint64, afterBalance, this.token.target, this.recipient),
      //   ).to.eventually.equal(1000n);
    });
  });
});
