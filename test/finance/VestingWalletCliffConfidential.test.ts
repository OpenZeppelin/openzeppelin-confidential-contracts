import { shouldBehaveLikeVestingConfidential } from './VestingWalletConfidential.behavior';
import { FhevmType } from '@fhevm/hardhat-plugin';
import { time } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { EventLog } from 'ethers';
import { ethers, fhevm } from 'hardhat';

const name = 'ConfidentialFungibleToken';
const symbol = 'CFT';
const uri = 'https://example.com/metadata';

for (const useInitializable of [false, true]) {
  describe(`VestingWalletCliffConfidential${useInitializable ? 'Initializable' : ''}`, function () {
    beforeEach(async function () {
      const accounts = (await ethers.getSigners()).slice(3);
      const [holder, recipient, operator] = accounts;

      const token = await ethers.deployContract('$ConfidentialFungibleTokenMock', [name, symbol, uri]);

      const encryptedInput = await fhevm
        .createEncryptedInput(await token.getAddress(), holder.address)
        .add64(1000)
        .encrypt();

      const currentTime = await time.latest();
      const schedule = [currentTime + 60, currentTime + 60 * 121];

      let vesting;
      let factory;
      let impl;

      if (!useInitializable) {
        vesting = await ethers.deployContract('$VestingWalletCliffConfidentialMock', [
          operator,
          recipient,
          currentTime + 60,
          60 * 60 * 2 /* 2 hours */,
          60 * 60 /* 1 hour */,
        ]);
      } else {
        impl = await ethers.deployContract('$VestingWalletCliffConfidentialInitializableMock');
        factory = await ethers.deployContract('Create2Factory');

        const callData = await impl.initialize.populateTransaction(
          operator,
          recipient,
          currentTime + 60,
          60 * 60 * 2 /* 2 hours */,
          60 * 60 /* 1 hour */,
        );
        const cloneTx = (await (await factory.create2(impl.target, callData.data)).wait())!;
        const cloneAddress = (cloneTx.logs[2] as EventLog).args[0];

        vesting = await ethers.getContractAt('$VestingWalletCliffConfidentialInitializableMock', cloneAddress);
      }

      await (token as any)
        .connect(holder)
        ['$_mint(address,bytes32,bytes)'](vesting.target, encryptedInput.handles[0], encryptedInput.inputProof);

      Object.assign(this, {
        accounts,
        holder,
        recipient,
        operator,
        token,
        vesting,
        schedule,
        vestingAmount: 1000,
        factory,
        impl,
      });
    });

    it('should release nothing before cliff', async function () {
      await time.increaseTo(this.schedule[0] + 60);
      await this.vesting.release(this.token);

      const balanceOfHandle = await this.token.balanceOf(this.recipient);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, balanceOfHandle, this.token.target, this.recipient),
      ).to.eventually.equal(0);
    });

    it('should fail construction if cliff is longer than duration', async function () {
      if (!useInitializable) {
        await expect(
          ethers.deployContract('$VestingWalletCliffConfidentialMock', [
            this.operator,
            this.recipient,
            (await time.latest()) + 60,
            60 * 10,
            60 * 60,
          ]),
        ).to.be.revertedWithCustomError(this.vesting, 'InvalidCliffDuration');
      } else {
        const callData = await this.impl.initialize.populateTransaction(
          this.operator,
          this.recipient,
          (await time.latest()) + 60,
          60 * 10,
          60 * 60,
        );
        await expect(this.factory.create2(this.impl.target, callData.data)).to.be.revertedWithCustomError(
          this.vesting,
          'InvalidCliffDuration',
        );
      }
    });

    if (useInitializable) {
      it('cannot reinitialize', async function () {
        await expect(
          this.vesting.initialize(
            this.operator,
            this.recipient,
            (await time.latest()) + 60,
            60 * 60 * 2 /* 2 hours */,
            60 * 60 /* 1 hour */,
          ),
        ).to.be.revertedWithCustomError(this.vesting, 'InvalidInitialization');
      });
    }

    shouldBehaveLikeVestingConfidential();
  });
}
