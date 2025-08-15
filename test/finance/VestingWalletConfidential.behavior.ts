import { $ConfidentialFungibleTokenMock } from '../../types/contracts-exposed/mocks/token/ConfidentialFungibleTokenMock.sol/$ConfidentialFungibleTokenMock';
import { FhevmType } from '@fhevm/hardhat-plugin';
import { time } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

function shouldBehaveLikeVestingConfidential() {
  describe('vesting', async function () {
    it('should release nothing before vesting start', async function () {
      await this.vesting.release(this.token);

      const balanceOfHandle = await this.token.confidentialBalanceOf(this.recipient);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, balanceOfHandle, this.token.target, this.recipient),
      ).to.eventually.equal(0);
    });

    it('should release nothing at vesting start', async function () {
      await time.increaseTo(this.schedule[0]);
      await this.vesting.release(this.token);

      const balanceOfHandle = await this.token.confidentialBalanceOf(this.recipient);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, balanceOfHandle, this.token.target, this.recipient),
      ).to.eventually.equal(0);
    });

    it('should release half at midpoint', async function () {
      await time.increaseTo((this.schedule[1] + this.schedule[0]) / 2);
      await this.vesting.release(this.token);

      const balanceOfHandle = await this.token.confidentialBalanceOf(this.recipient);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, balanceOfHandle, this.token.target, this.recipient),
      ).to.eventually.equal(this.vestingAmount / 2);
    });

    it('should release entire amount after end', async function () {
      await time.increaseTo(this.schedule[1] + 1000);
      await this.vesting.release(this.token);

      const balanceOfHandle = await this.token.confidentialBalanceOf(this.recipient);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, balanceOfHandle, this.token.target, this.recipient),
      ).to.eventually.equal(this.vestingAmount);
    });

    it('should not release if reentrancy', async function () {
      const reentrantToken = await ethers.deployContract('$ConfidentialFungibleTokenReentrantMock', [
        'name',
        'symbol',
        'uri',
      ]);
      const encryptedInput = await fhevm
        .createEncryptedInput(await reentrantToken.getAddress(), this.holder.address)
        .add64(1000)
        .encrypt();
      await (reentrantToken as any as $ConfidentialFungibleTokenMock)
        .connect(this.holder)
        ['$_mint(address,bytes32,bytes)'](this.vesting.target, encryptedInput.handles[0], encryptedInput.inputProof);

      await expect(this.vesting.release(reentrantToken)).to.be.revertedWithCustomError(
        this.vesting,
        'ReentrancyGuardReentrantCall',
      );
    });
  });

  it('should fail to init if not initializing', async function () {
    await expect(
      this.vesting.$__VestingWalletConfidential_init(this.recipient, await time.latest(), 60 * 60),
    ).to.be.revertedWithCustomError(this.vesting, 'NotInitializing');
  });
}

export { shouldBehaveLikeVestingConfidential };
