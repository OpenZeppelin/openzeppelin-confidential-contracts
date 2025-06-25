import { createInstance } from '../_template/instance';
import { reencryptEuint64 } from '../_template/reencrypt';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import { time } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { ethers } from 'hardhat';

const name = 'ConfidentialFungibleToken';
const symbol = 'CFT';
const uri = 'https://example.com/metadata';

describe('VestingConfidential', function () {
  beforeEach(async function () {
    const accounts = await ethers.getSigners();
    const [holder, recipient, operator] = accounts;

    const token = await ethers.deployContract('$ConfidentialFungibleTokenMock', [name, symbol, uri]);
    this.accounts = accounts.slice(3);
    this.holder = holder;
    this.recipient = recipient;
    this.token = token;
    this.operator = operator;
    this.fhevm = await createInstance();

    const input = this.fhevm.createEncryptedInput(this.token.target, this.holder.address);
    input.add64(1000);
    const encryptedInput = await input.encrypt();

    await this.token
      .connect(this.holder)
      ['$_mint(address,bytes32,bytes)'](this.holder, encryptedInput.handles[0], encryptedInput.inputProof);

    this.vesting = await ethers.deployContract('$VestingConfidentialMock', [this.token]);
    await this.token.$_setOperator(this.holder, this.vesting, Math.round(Date.now() / 1000) + 100);
  });

  it('create vesting', async function () {
    const input = this.fhevm.createEncryptedInput(this.vesting.target, this.holder.address);
    input.add64(500);
    const totalVestingAmount = await input.encrypt();

    const input2 = this.fhevm.createEncryptedInput(this.vesting.target, this.holder.address);
    input2.add64(5);
    const vestingPerSecond = await input2.encrypt();

    await this.vesting
      .connect(this.holder)
      .createVestingStream(
        Math.round(Date.now() / 1000) + 10,
        this.recipient.address,
        totalVestingAmount.handles[0],
        vestingPerSecond.handles[0],
        totalVestingAmount.inputProof,
        vestingPerSecond.inputProof,
      );
  });

  describe('with stream vesting', function () {
    beforeEach(async function () {
      const vestingStartTime = (await time.latest()) + 10;
      const input = this.fhevm.createEncryptedInput(this.vesting.target, this.holder.address);
      input.add64(500);
      const totalVestingAmount = await input.encrypt();

      const input2 = this.fhevm.createEncryptedInput(this.vesting.target, this.holder.address);
      input2.add64(5);
      const vestingPerSecond = await input2.encrypt();

      await this.vesting
        .connect(this.holder)
        .createVestingStream(
          vestingStartTime,
          this.recipient.address,
          totalVestingAmount.handles[0],
          vestingPerSecond.handles[0],
          totalVestingAmount.inputProof,
          vestingPerSecond.inputProof,
        );

      const vestingStream = {
        startTime: vestingStartTime,
        vestingPerSecond: 5,
        id: 1,
      };

      this.vestingStream = vestingStream;
    });

    describe('claim', function () {
      it('from commingled funds', async function () {
        await time.setNextBlockTimestamp(this.vestingStream.startTime + 10);
        await this.vesting.connect(this.recipient).claim(this.vestingStream.id);

        let recipientBalanceHandle = await this.token.balanceOf(this.recipient);
        await expect(
          reencryptEuint64(this.recipient, this.fhevm, recipientBalanceHandle, this.token.target),
        ).to.eventually.equal(this.vestingStream.vestingPerSecond * 10);

        await time.setNextBlockTimestamp(this.vestingStream.startTime + 11);
        await this.vesting.connect(this.recipient).claim(this.vestingStream.id);

        recipientBalanceHandle = await this.token.balanceOf(this.recipient);
        await expect(
          reencryptEuint64(this.recipient, this.fhevm, recipientBalanceHandle, this.token.target),
        ).to.eventually.equal(this.vestingStream.vestingPerSecond * 11);
      });

      it('from managed vault', async function () {
        await expect(this.vesting.connect(this.recipient).createManagedVault(this.vestingStream.id)).to.emit(
          this.vesting,
          'VestingBaseManagedVaultCreated',
        );

        await time.setNextBlockTimestamp(this.vestingStream.startTime + 10);
        const tx = await this.vesting.connect(this.recipient).claim(this.vestingStream.id);

        const transferEvent = (await tx.wait()).logs.filter((log: any) => log.address === this.token.target)[0];
        expect(transferEvent.topics[1]).to.not.equal(
          ethers.AbiCoder.defaultAbiCoder().encode(['address'], [this.vesting.target]),
        );
        expect(transferEvent.topics[2]).to.equal(
          ethers.AbiCoder.defaultAbiCoder().encode(['address'], [this.recipient.address]),
        );

        await expect(
          reencryptEuint64(this.recipient, this.fhevm, BigInt(transferEvent.topics[3]), this.token.target),
        ).to.eventually.equal(this.vestingStream.vestingPerSecond * 10);
      });
    });

    describe('managed vault', async function () {
      it('creation works', async function () {
        const tx = await this.vesting.connect(this.recipient).createManagedVault(this.vestingStream.id);

        const managedVaultCreationEvent = (await tx.wait()).logs.filter(
          (log: any) => log.address === this.vesting.target,
        )[0];

        expect(tx).to.emit(this.vesting, 'VestingBaseManagedVaultCreated');
        expect(tx)
          .to.emit(this.token, 'ConfidentialTransfer')
          .withArgs(this.vesting, managedVaultCreationEvent.args[1], anyValue);
        expect(tx).to.emit(this.token, 'OperatorSet');
      });

      it("can't create twice", async function () {
        await this.vesting.connect(this.recipient).createManagedVault(this.vestingStream.id);
        await expect(this.vesting.connect(this.recipient).createManagedVault(this.vestingStream.id))
          .to.be.revertedWithCustomError(this.vesting, 'VestingBaseMangedVaultAlreadyExists')
          .withArgs(1, anyValue);
      });

      it('only stream recipient can create', async function () {
        await expect(this.vesting.connect(this.operator).createManagedVault(this.vestingStream.id))
          .to.be.revertedWithCustomError(this.vesting, 'VestingBaseOnlyRecipient')
          .withArgs(this.recipient);
      });
    });
  });
});
