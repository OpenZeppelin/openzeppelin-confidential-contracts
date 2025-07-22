import { shouldBehaveLikeVestingConfidential } from './VestingWalletConfidential.behavior';
import { FhevmType } from '@fhevm/hardhat-plugin';
import { time } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

const name = 'ConfidentialFungibleToken';
const symbol = 'CFT';
const uri = 'https://example.com/metadata';

describe(`VestingWalletCliffConfidential`, function () {
  beforeEach(async function () {
    const accounts = (await ethers.getSigners()).slice(3);
    const [holder, recipient] = accounts;

    const token = await ethers.deployContract('$ConfidentialFungibleTokenMock', [name, symbol, uri]);

    const encryptedInput = await fhevm
      .createEncryptedInput(await token.getAddress(), holder.address)
      .add64(1000)
      .encrypt();

    const currentTime = await time.latest();
    const schedule = [currentTime + 60, currentTime + 60 * 121];

    const vesting = await ethers.deployContract('$VestingWalletCliffConfidentialMock', [
      recipient,
      currentTime + 60,
      60 * 60 * 2 /* 2 hours */,
      60 * 60 /* 1 hour */,
    ]);

    await (token as any)
      .connect(holder)
      ['$_mint(address,bytes32,bytes)'](vesting.target, encryptedInput.handles[0], encryptedInput.inputProof);

    Object.assign(this, {
      accounts,
      holder,
      recipient,
      token,
      vesting,
      schedule,
      vestingAmount: 1000,
    });
  });

  it('should release nothing before cliff', async function () {
    await time.increaseTo(this.schedule[0] + 60);
    await this.vesting.release(this.token);

    const balanceOfHandle = await this.token.confidentialBalanceOf(this.recipient);
    await expect(
      fhevm.userDecryptEuint(FhevmType.euint64, balanceOfHandle, this.token.target, this.recipient),
    ).to.eventually.equal(0);
  });

  it('should fail construction if cliff is longer than duration', async function () {
    await expect(
      ethers.deployContract('$VestingWalletCliffConfidentialMock', [
        this.recipient,
        (await time.latest()) + 60,
        60 * 10,
        60 * 60,
      ]),
    ).to.be.revertedWithCustomError(this.vesting, 'VestingWalletCliffConfidentialInvalidCliffDuration');
  });

  it('should fail to init if not initializing', async function () {
    await expect(this.vesting.$__VestingWalletCliffConfidential_init(60 * 10 - 1)).to.be.revertedWithCustomError(
      this.vesting,
      'NotInitializing',
    );
  });

  shouldBehaveLikeVestingConfidential();
});
