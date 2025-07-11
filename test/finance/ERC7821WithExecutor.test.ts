import { ERC7821WithExecutor } from '../../types';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

const name = 'ConfidentialFungibleToken';
const symbol = 'CFT';
const uri = 'https://example.com/metadata';
const mode = ethers.solidityPacked(
  ['bytes1', 'bytes1', 'bytes4', 'bytes4', 'bytes22'],
  ['0x01', '0x00', '0x00000000', '0x00000000', '0x00000000000000000000000000000000000000000000'],
);

describe('ERC7821WithExecutor', function () {
  beforeEach(async function () {
    const accounts = (await ethers.getSigners()).slice(2);
    const [recipient, executor] = await ethers.getSigners();

    const token = await ethers.deployContract('$ConfidentialFungibleTokenMock', [name, symbol, uri]);

    const encryptedInput = await fhevm
      .createEncryptedInput(await token.getAddress(), recipient.address)
      .add64(1000)
      .encrypt();

    const executorWallet = (await ethers.deployContract('$ERC7821WithExecutor', [
      executor,
    ])) as unknown as ERC7821WithExecutor;

    await (token as any)
      .connect(recipient)
      ['$_mint(address,bytes32,bytes)'](executorWallet.target, encryptedInput.handles[0], encryptedInput.inputProof);

    Object.assign(this, { accounts, recipient, executor, executorWallet, token });
  });

  describe('call', async function () {
    it('should fail if not called by executor', async function () {
      await expect(this.executorWallet.execute(mode, '0x')).to.be.revertedWithCustomError(
        this.executorWallet,
        'AccountUnauthorized',
      );
    });

    it('should call if called by executor', async function () {
      const executionCalls = ethers.AbiCoder.defaultAbiCoder().encode(
        ['(address,uint256,bytes)[]'],
        [
          [
            [
              this.token.target,
              0,
              (
                await this.token.confidentialTransfer.populateTransaction(
                  this.recipient,
                  await this.token.confidentialBalanceOf(this.executorWallet),
                )
              ).data,
            ],
          ],
        ],
      );
      await expect(this.executorWallet.connect(this.executor).execute(mode, executionCalls))
        .to.emit(this.token, 'ConfidentialTransfer')
        .withArgs(this.executorWallet, this.recipient, anyValue);
    });
  });
});
