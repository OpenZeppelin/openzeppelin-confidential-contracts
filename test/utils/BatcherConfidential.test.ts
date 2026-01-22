import { IERC165__factory, IERC7984__factory } from '../../../types';
import { allowHandle } from '../../helpers/accounts';
import { getFunctions, getInterfaceId } from '../../helpers/interface';
import { ERC7984ERC20WrapperMock } from '../../types';
import { FhevmType } from '@fhevm/hardhat-plugin';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import { expect } from 'chai';
import hre, { ethers, fhevm } from 'hardhat';

const name = 'ConfidentialFungibleToken';
const symbol = 'CFT';
const uri = 'https://example.com/metadata';

describe('BatcherConfidential', function () {
  beforeEach(async function () {
    const accounts = await ethers.getSigners();
    const [holder, recipient, operator] = accounts;

    const fromTokenUnderlying = await ethers.deployContract('$ERC20Mock', [name, symbol, 18]);
    const toTokenUnderlying = await ethers.deployContract('$ERC20Mock', [name, symbol, 18]);

    const fromToken = await ethers.deployContract('$ERC7984ERC20WrapperMock', [fromTokenUnderlying, name, symbol, uri]);
    const toToken = await ethers.deployContract('$ERC7984ERC20WrapperMock', [toTokenUnderlying, name, symbol, uri]);

    for (const tokens of [
      { underlying: fromTokenUnderlying, wrapper: fromToken },
      { underlying: toTokenUnderlying, wrapper: toToken },
    ]) {
      await tokens.underlying.$_mint(holder, ethers.parseEther('1'));
      await (tokens.underlying.connect(holder) as any).approve(tokens.wrapper, ethers.parseEther('1'));
      await tokens.wrapper.wrap(holder, ethers.parseEther('1'));
    }

    Object.assign(this, {
      fromTokenUnderlying,
      toTokenUnderlying,
      fromToken,
      toToken,
      accounts: accounts.slice(3),
      holder,
      recipient,
      operator,
    });
  });

  describe('route via exchange', async function () {
    beforeEach(async function () {
      const exchange = await ethers.deployContract('$ExchangeMock', [
        this.fromTokenUnderlying,
        this.toTokenUnderlying,
        ethers.parseEther('1'),
      ]);

      await Promise.all(
        [this.fromTokenUnderlying, this.toTokenUnderlying].map(async token => {
          await token.$_mint(exchange, ethers.parseEther('1000'));
        }),
      );

      const batcher = await ethers.deployContract('$BatcherConfidentialSwapMock', [
        this.fromToken,
        this.toToken,
        exchange,
      ]);

      await this.fromToken.connect(this.holder).setOperator(batcher, Math.round(Date.now() / 1000) + 1000);

      this.batcher = batcher;
    });

    it('happy path', async function () {
      const joinAmount = await fhevm
        .createEncryptedInput(this.batcher.target, this.holder.address)
        .add64(1000)
        .encrypt();

      await this.batcher.connect(this.holder).join(joinAmount.handles[0], joinAmount.inputProof);
      await this.batcher.connect(this.holder).dispatchBatch();

      const [, amount] = (await this.fromToken.queryFilter(this.fromToken.filters.UnwrapRequested()))[0].args;
      const { abiEncodedClearValues, decryptionProof } = await fhevm.publicDecrypt([amount]);

      await this.batcher.dispatchBatchCallback(1, abiEncodedClearValues, decryptionProof);
      await this.batcher.connect(this.holder).exit(1);
    });

    it.only('unwrap already finalized', async function () {
      const joinAmount = await fhevm
        .createEncryptedInput(this.batcher.target, this.holder.address)
        .add64(1000)
        .encrypt();

      await this.batcher.connect(this.holder).join(joinAmount.handles[0], joinAmount.inputProof);
      await this.batcher.connect(this.holder).dispatchBatch();

      await publicDecryptAndFinalizeUnwrap(this.fromToken, this.holder);

      const [, amount] = (await this.fromToken.queryFilter(this.fromToken.filters.UnwrapRequested()))[0].args;
      const { abiEncodedClearValues, decryptionProof } = await fhevm.publicDecrypt([amount]);

      await this.batcher.dispatchBatchCallback(1, abiEncodedClearValues, decryptionProof);
      await this.batcher.connect(this.holder).exit(1);
    });

    it('unwrap already finalized, invalid callback value', async function () {
      const joinAmount = await fhevm
        .createEncryptedInput(this.batcher.target, this.holder.address)
        .add64(1000)
        .encrypt();

      await this.batcher.connect(this.holder).join(joinAmount.handles[0], joinAmount.inputProof);
      await this.batcher.connect(this.holder).dispatchBatch();

      await publicDecryptAndFinalizeUnwrap(this.fromToken, this.holder);

      const [, amount] = (await this.fromToken.queryFilter(this.fromToken.filters.UnwrapRequested()))[0].args;
      const { abiEncodedClearValues, decryptionProof } = await fhevm.publicDecrypt([amount]);

      await expect(this.batcher.dispatchBatchCallback(1, BigInt(abiEncodedClearValues) + 1n, decryptionProof)).to.be
        .reverted;
    });
  });
});

async function publicDecryptAndFinalizeUnwrap(wrapper: ERC7984ERC20WrapperMock, caller: HardhatEthersSigner) {
  const [to, amount] = (await wrapper.queryFilter(wrapper.filters.UnwrapRequested()))[0].args;
  const { abiEncodedClearValues, decryptionProof } = await fhevm.publicDecrypt([amount]);
  await expect(wrapper.connect(caller).finalizeUnwrap(amount, abiEncodedClearValues, decryptionProof))
    .to.emit(wrapper, 'UnwrapFinalized')
    .withArgs(to, amount, abiEncodedClearValues);
}
