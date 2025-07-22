import { $ERC7821WithExecutor } from '../../types/contracts-exposed/finance/ERC7821WithExecutor.sol/$ERC7821WithExecutor';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import { encodeMode, encodeBatch, CALL_TYPE_BATCH } from '@openzeppelin/contracts/test/helpers/erc7579';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

const name = 'ConfidentialFungibleToken';
const symbol = 'CFT';
const uri = 'https://example.com/metadata';

describe('ERC7821WithExecutor', function () {
  beforeEach(async function () {
    const [recipient, executor, ...accounts] = await ethers.getSigners();

    const token = await ethers.deployContract('$ConfidentialFungibleTokenMock', [name, symbol, uri]);

    const encryptedInput = await fhevm
      .createEncryptedInput(await token.getAddress(), recipient.address)
      .add64(1000)
      .encrypt();

    const executorWallet = (await ethers.deployContract('$ERC7821WithExecutor', [
      executor,
    ])) as unknown as $ERC7821WithExecutor;

    await (token as any)
      .connect(recipient)
      ['$_mint(address,bytes32,bytes)'](executorWallet.target, encryptedInput.handles[0], encryptedInput.inputProof);

    Object.assign(this, { accounts, recipient, executor, executorWallet, token });
  });

  describe('call', async function () {
    it('should fail if not called by executor', async function () {
      await expect(this.executorWallet.connect(this.recipient).execute(ethers.ZeroHash, '0x'))
        .to.be.revertedWithCustomError(this.executorWallet, 'AccountUnauthorized')
        .withArgs(this.recipient);
    });

    it('should call if called by executor', async function () {
      const balance = await this.token.confidentialBalanceOf(this.executorWallet);

      await expect(
        this.executorWallet.connect(this.executor).execute(
          encodeMode({ callType: CALL_TYPE_BATCH }),
          encodeBatch({
            target: this.token,
            value: 0n,
            data: this.token.interface.encodeFunctionData('confidentialTransfer(address,bytes32)', [
              this.recipient.address,
              balance,
            ]),
          }),
        ),
      )
        .to.emit(this.token, 'ConfidentialTransfer')
        .withArgs(this.executorWallet, this.recipient, anyValue);
    });

    it('should call if called by itself', async function () {
      const balance = await this.token.confidentialBalanceOf(this.executorWallet);

      await expect(
        // caller is executor account
        this.executorWallet.connect(this.executor).execute(
          encodeMode({ callType: CALL_TYPE_BATCH }),
          encodeBatch({
            target: this.executorWallet.target,
            value: 0n,
            // then caller is `ERC7821WithExecutor` contract
            data: this.executorWallet.interface.encodeFunctionData('execute(bytes32,bytes)', [
              encodeMode({ callType: CALL_TYPE_BATCH }),
              encodeBatch({
                target: this.token,
                value: 0n,
                data: this.token.interface.encodeFunctionData('confidentialTransfer(address,bytes32)', [
                  this.recipient.address,
                  balance,
                ]),
              }),
            ]),
          }),
        ),
      )
        .to.emit(this.token, 'ConfidentialTransfer')
        .withArgs(this.executorWallet, this.recipient, anyValue);
    });
  });

  it('should fail to init if not initializing', async function () {
    await expect(this.executorWallet.$__ERC7821WithExecutor_init(this.executor)).to.be.revertedWithCustomError(
      this.executorWallet,
      'NotInitializing',
    );
  });
});
