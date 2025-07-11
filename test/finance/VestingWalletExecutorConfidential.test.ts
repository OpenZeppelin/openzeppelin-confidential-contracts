import { VestingWalletExecutorConfidentialMock } from '../../types';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import { time } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

const name = 'ConfidentialFungibleToken';
const symbol = 'CFT';
const uri = 'https://example.com/metadata';
const mode = ethers.solidityPacked(
  ['bytes1', 'bytes1', 'bytes4', 'bytes4', 'bytes22'],
  ['0x01', '0x00', '0x00000000', '0x00000000', '0x00000000000000000000000000000000000000000000'],
);
let vesting: VestingWalletExecutorConfidentialMock;

//TODO: Rename file/name to WithExecutor
describe('VestingWalletExecutorConfidential', function () {
  beforeEach(async function () {
    const accounts = (await ethers.getSigners()).slice(3);
    const [holder, recipient, executor] = accounts;

    const token = await ethers.deployContract('$ConfidentialFungibleTokenMock', [name, symbol, uri]);

    const encryptedInput = await fhevm
      .createEncryptedInput(await token.getAddress(), holder.address)
      .add64(1000)
      .encrypt();

    const currentTime = await time.latest();
    const schedule = [currentTime + 60, currentTime + 60 * 61];
    vesting = (await ethers.deployContract('$VestingWalletExecutorConfidentialMock', [
      recipient,
      currentTime + 60,
      60 * 60 /* 1 hour */,
      executor,
    ])) as any as VestingWalletExecutorConfidentialMock;

    await (token as any)
      .connect(holder)
      ['$_mint(address,bytes32,bytes)'](vesting.target, encryptedInput.handles[0], encryptedInput.inputProof);

    Object.assign(this, { accounts, holder, recipient, executor, token, schedule, vestingAmount: 1000 });
  });

  describe('call', async function () {
    it('should fail if not called by executor', async function () {
      await expect(vesting.execute(mode, '0x')).to.be.revertedWithCustomError(vesting, 'AccountUnauthorized');
    });

    it('should call if called by executor', async function () {
      await expect(
        vesting
          .connect(this.executor)
          .execute(
            mode,
            ethers.AbiCoder.defaultAbiCoder().encode(
              ['(address,uint256,bytes)[]'],
              [
                [
                  [
                    this.token.target,
                    0,
                    (
                      await this.token.confidentialTransfer.populateTransaction(
                        this.recipient,
                        await this.token.confidentialBalanceOf(vesting),
                      )
                    ).data,
                  ],
                ],
              ],
            ),
          ),
      )
        .to.emit(this.token, 'ConfidentialTransfer')
        .withArgs(vesting, this.recipient, anyValue);
    });
  });
});
