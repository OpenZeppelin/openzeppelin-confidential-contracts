import { $ERC20Mock } from '../../types/contracts-exposed/mocks/token/ERC20Mock.sol/$ERC20Mock';
import { $ERC7984ERC20Wrapper } from '../../types/contracts-exposed/token/ERC7984/extensions/ERC7984ERC20Wrapper.sol/$ERC7984ERC20Wrapper';
import { FhevmType } from '@fhevm/hardhat-plugin';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

const name = 'ConfidentialFungibleToken';
const symbol = 'CFT';
const uri = 'https://example.com/metadata';
const wrapAmount = BigInt(ethers.parseEther('10'));
const exchangeRateDecimals = 6n;
const exchangeRateMantissa = 10n ** exchangeRateDecimals;

enum BatchState {
  Pending,
  Dispatched,
  Finalized,
}

describe('BatcherConfidential', function () {
  beforeEach(async function () {
    const accounts = await ethers.getSigners();
    const [holder, recipient, operator] = accounts;

    const fromTokenUnderlying = (await ethers.deployContract('$ERC20Mock', [name, symbol, 18])) as any as $ERC20Mock;
    const toTokenUnderlying = (await ethers.deployContract('$ERC20Mock', [name, symbol, 18])) as any as $ERC20Mock;

    const fromToken = (await ethers.deployContract('$ERC7984ERC20WrapperMock', [
      fromTokenUnderlying,
      name,
      symbol,
      uri,
    ])) as any as $ERC7984ERC20Wrapper;
    const toToken = (await ethers.deployContract('$ERC7984ERC20WrapperMock', [
      toTokenUnderlying,
      name,
      symbol,
      uri,
    ])) as any as $ERC7984ERC20Wrapper;

    for (const { to, tokens } of [holder, recipient].flatMap(x =>
      [
        { underlying: fromTokenUnderlying, wrapper: fromToken },
        { underlying: toTokenUnderlying, wrapper: toToken },
      ].map(y => {
        return { to: x, tokens: y };
      }),
    )) {
      await tokens.underlying.$_mint(to, wrapAmount);
      await tokens.underlying.connect(to).approve(tokens.wrapper, wrapAmount);
      await tokens.wrapper.connect(to).wrap(to, wrapAmount);
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
      fromTokenRate: BigInt(await fromToken.rate()),
      toTokenRate: BigInt(await toToken.rate()),
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
        this.operator,
      ]);

      for (const approver of [this.holder, this.recipient]) {
        await this.fromToken.connect(approver).setOperator(batcher, 2n ** 48n - 1n);
      }

      this.batcher = batcher;
    });

    describe('join', async function () {
      it('should increase individual deposits', async function () {
        const batchId = await this.batcher.currentBatchId();

        await expect(this.batcher.deposits(batchId, this.holder)).to.eventually.eq(ethers.ZeroHash);

        await this.batcher.join(1000);

        await expect(
          fhevm.userDecryptEuint(
            FhevmType.euint64,
            await this.batcher.deposits(batchId, this.holder),
            this.batcher,
            this.holder,
          ),
        ).to.eventually.eq('1000');

        await this.batcher.join(2000);

        await expect(
          fhevm.userDecryptEuint(
            FhevmType.euint64,
            await this.batcher.deposits(batchId, this.holder),
            this.batcher,
            this.holder,
          ),
        ).to.eventually.eq('3000');
      });

      it('should increase total deposits', async function () {
        const batchId = await this.batcher.currentBatchId();

        await this.batcher.join(1000);
        await this.batcher.connect(this.recipient).join(2000);

        await expect(
          fhevm.userDecryptEuint(
            FhevmType.euint64,
            await this.batcher.totalDeposits(batchId),
            this.batcher,
            this.operator,
          ),
        ).to.eventually.eq('3000');
      });

      it('should emit event', async function () {
        const batchId = await this.batcher.currentBatchId();

        await expect(this.batcher.join(1000))
          .to.emit(this.batcher, 'Joined')
          .withArgs(batchId, this.holder.address, anyValue);
      });

      it('should not credit failed transaction', async function () {
        const batchId = await this.batcher.currentBatchId();

        await this.batcher.join(wrapAmount / this.fromTokenRate + 1n);

        await expect(
          fhevm.userDecryptEuint(
            FhevmType.euint64,
            await this.batcher.deposits(batchId, this.holder),
            this.batcher,
            this.holder,
          ),
        ).to.eventually.eq(0);
      });
    });

    describe('claim', function () {
      beforeEach(async function () {
        this.batchId = await this.batcher.currentBatchId();

        await this.batcher.join(1000);
        await this.batcher.connect(this.holder).dispatchBatch();

        const [, amount] = (await this.fromToken.queryFilter(this.fromToken.filters.UnwrapRequested()))[0].args;
        const { abiEncodedClearValues, decryptionProof } = await fhevm.publicDecrypt([amount]);
        await this.batcher.dispatchBatchCallback(this.batchId, abiEncodedClearValues, decryptionProof);

        this.exchangeRate = BigInt(await this.batcher.exchangeRate(this.batchId));
        this.deposit = 1000n;
      });

      it('should clear deposits', async function () {
        await this.batcher.claim(this.batchId);

        await expect(
          fhevm.userDecryptEuint(
            FhevmType.euint64,
            await this.batcher.deposits(this.batchId, this.holder),
            this.batcher,
            this.holder,
          ),
        ).to.eventually.eq(0);
      });

      it('should transfer out correct amount of toToken', async function () {
        const beforeBalanceToTokens = await fhevm.userDecryptEuint(
          FhevmType.euint64,
          await this.toToken.confidentialBalanceOf(this.holder),
          this.toToken,
          this.holder,
        );

        await this.batcher.claim(this.batchId);

        await expect(
          fhevm.userDecryptEuint(
            FhevmType.euint64,
            await this.toToken.confidentialBalanceOf(this.holder),
            this.toToken,
            this.holder,
          ),
        ).to.eventually.eq(
          BigInt(beforeBalanceToTokens) + BigInt(this.exchangeRate * this.deposit) / exchangeRateMantissa,
        );
      });

      it('should revert if not finalized', async function () {
        const currentBatchId = await this.batcher.currentBatchId();
        await expect(this.batcher.claim(currentBatchId))
          .to.be.revertedWithCustomError(this.batcher, 'BatchUnexpectedState')
          .withArgs(currentBatchId, BatchState.Pending, BatchState.Finalized);
      });

      it('should emit event', async function () {
        await expect(this.batcher.claim(this.batchId))
          .to.emit(this.batcher, 'Claimed')
          .withArgs(this.batchId, this.holder.address, anyValue);
      });

      it('should allow retry claim (idempotent when fully claimed)', async function () {
        // First claim should succeed and clear deposits
        await this.batcher.claim(this.batchId);

        // Verify deposits are cleared
        await expect(
          fhevm.userDecryptEuint(
            FhevmType.euint64,
            await this.batcher.deposits(this.batchId, this.holder),
            this.batcher,
            this.holder,
          ),
        ).to.eventually.eq(0);

        // Second claim should succeed (return 0, no-op since no deposit left)
        await expect(this.batcher.claim(this.batchId)).to.emit(this.batcher, 'Claimed');

        // Deposits should still be zero
        await expect(
          fhevm.userDecryptEuint(
            FhevmType.euint64,
            await this.batcher.deposits(this.batchId, this.holder),
            this.batcher,
            this.holder,
          ),
        ).to.eventually.eq(0);
      });

      it('should track failed claims properly', async function () {
        // TODO: implement this once merging in #301
      });
    });

    describe('quit', function () {
      beforeEach(async function () {
        this.batchId = await this.batcher.currentBatchId();
        this.deposit = 1000n;

        await this.batcher.join(this.deposit);
      });

      it('should send back full deposit', async function () {
        const beforeBalance = await fhevm.userDecryptEuint(
          FhevmType.euint64,
          await this.fromToken.confidentialBalanceOf(this.holder),
          this.fromToken,
          this.holder,
        );

        await this.batcher.quit(this.batchId);

        await expect(
          fhevm.userDecryptEuint(
            FhevmType.euint64,
            await this.fromToken.confidentialBalanceOf(this.holder),
            this.fromToken,
            this.holder,
          ),
        ).to.eventually.eq(beforeBalance + this.deposit);

        await expect(
          fhevm.userDecryptEuint(
            FhevmType.euint64,
            await this.batcher.deposits(this.batchId, this.holder),
            this.batcher,
            this.holder,
          ),
        ).to.eventually.eq(0);
      });

      it('should decrease total deposits', async function () {
        await this.batcher.quit(this.batchId);

        await expect(
          fhevm.userDecryptEuint(
            FhevmType.euint64,
            await this.batcher.totalDeposits(this.batchId),
            this.batcher,
            this.operator,
          ),
        ).to.eventually.eq(0);
      });

      it('should fail if batch already dispatched', async function () {
        await this.batcher.connect(this.holder).dispatchBatch();

        await expect(this.batcher.quit(this.batchId))
          .to.be.revertedWithCustomError(this.batcher, 'BatchUnexpectedState')
          .withArgs(this.batchId, BatchState.Dispatched, BatchState.Pending);
      });

      it('should emit event', async function () {
        await expect(this.batcher.quit(this.batchId))
          .to.emit(this.batcher, 'Quit')
          .withArgs(this.batchId, this.holder.address, anyValue);
      });
    });

    describe('set exchange rate', function () {
      beforeEach(async function () {
        this.batchId = await this.batcher.currentBatchId();
      });

      it('should succeed if in bounds', async function () {
        await this.batcher.connect(this.holder).join(1000);

        await this.batcher.connect(this.holder).dispatchBatch();
        await this.batcher.shouldSetExchangeRate(false);

        const rate = 10n ** 9n;
        await this.batcher.$_setExchangeRate(this.batchId, rate);
      });

      it('should revert if 0', async function () {
        await this.batcher.connect(this.holder).join(1000);

        await this.batcher.connect(this.holder).dispatchBatch();
        await this.batcher.shouldSetExchangeRate(false);

        const [, amount] = (await this.fromToken.queryFilter(this.fromToken.filters.UnwrapRequested()))[0].args;
        const { abiEncodedClearValues, decryptionProof } = await fhevm.publicDecrypt([amount]);
        await this.batcher.dispatchBatchCallback(this.batchId, abiEncodedClearValues, decryptionProof);

        await expect(this.batcher.$_setExchangeRate(this.batchId, 0n))
          .to.be.revertedWithCustomError(this.batcher, 'InvalidExchangeRate')
          .withArgs(this.batchId, 1000n, 0n);
      });

      it('should revert if too large', async function () {
        const joinAmount = wrapAmount / this.fromTokenRate;

        await this.batcher.connect(this.holder).join(joinAmount);

        await this.batcher.connect(this.holder).dispatchBatch();
        await this.batcher.shouldSetExchangeRate(false);

        const [, amount] = (await this.fromToken.queryFilter(this.fromToken.filters.UnwrapRequested()))[0].args;
        const { abiEncodedClearValues, decryptionProof } = await fhevm.publicDecrypt([amount]);
        await this.batcher.dispatchBatchCallback(this.batchId, abiEncodedClearValues, decryptionProof);

        const uint64_max = 2n ** 64n - 1n;
        const rate = (uint64_max / joinAmount + 1n) * exchangeRateMantissa;

        await expect(this.batcher.$_setExchangeRate(this.batchId, rate))
          .to.be.revertedWithCustomError(this.batcher, 'InvalidExchangeRate')
          .withArgs(this.batchId, joinAmount, rate);
      });

      it('should set exchange rate', async function () {
        await this.batcher.connect(this.holder).join(1000);

        await this.batcher.connect(this.holder).dispatchBatch();
        await this.batcher.shouldSetExchangeRate(false);

        await this.batcher.$_setExchangeRate(this.batchId, 10n ** 7n);
        await expect(this.batcher.exchangeRate(1)).to.eventually.eq(10n ** 7n);
      });

      it('should fail if already set', async function () {
        await this.batcher.connect(this.holder).join(100n);

        await this.batcher.connect(this.holder).dispatchBatch();
        await this.batcher.shouldSetExchangeRate(false);

        const [, amount] = (await this.fromToken.queryFilter(this.fromToken.filters.UnwrapRequested()))[0].args;
        const { abiEncodedClearValues, decryptionProof } = await fhevm.publicDecrypt([amount]);
        await this.batcher.dispatchBatchCallback(this.batchId, abiEncodedClearValues, decryptionProof);

        await this.batcher.$_setExchangeRate(1, 10n ** 7n);

        await expect(this.batcher.$_setExchangeRate(1, 10n ** 7n))
          .to.be.revertedWithCustomError(this.batcher, 'BatchUnexpectedState')
          .withArgs(1n, BatchState.Finalized, BatchState.Dispatched);
      });

      it('should emit event', async function () {
        await this.batcher.connect(this.holder).join(100n);

        await this.batcher.connect(this.holder).dispatchBatch();
        await this.batcher.shouldSetExchangeRate(false);

        const [, amount] = (await this.fromToken.queryFilter(this.fromToken.filters.UnwrapRequested()))[0].args;
        const { abiEncodedClearValues, decryptionProof } = await fhevm.publicDecrypt([amount]);
        await this.batcher.dispatchBatchCallback(this.batchId, abiEncodedClearValues, decryptionProof);

        const rate = 10n ** 7n;
        await expect(this.batcher.$_setExchangeRate(1, rate))
          .to.emit(this.batcher, 'ExchangeRateSet')
          .withArgs(1, rate);
      });
    });

    describe('dispatchBatchCallback', function () {
      beforeEach(async function () {
        const batchId = await this.batcher.currentBatchId();

        await this.batcher.connect(this.holder).join(1000);
        await this.batcher.connect(this.holder).dispatchBatch();

        const [, amount] = (await this.fromToken.queryFilter(this.fromToken.filters.UnwrapRequested()))[0].args;
        const { abiEncodedClearValues, decryptionProof } = await fhevm.publicDecrypt([amount]);

        Object.assign(this, { batchId, unwrapAmount: amount, abiEncodedClearValues, decryptionProof });

        await expect(this.batcher.unwrapAmount(batchId)).to.eventually.eq(amount);
      });

      it('should finalize unwrap', async function () {
        await expect(this.batcher.dispatchBatchCallback(this.batchId, this.abiEncodedClearValues, this.decryptionProof))
          .to.emit(this.fromToken, 'UnwrapFinalized')
          .withArgs(this.batcher, this.unwrapAmount, this.abiEncodedClearValues);
      });

      it('should revert if proof validation fails', async function () {
        await this.fromToken.finalizeUnwrap(this.unwrapAmount, this.abiEncodedClearValues, this.decryptionProof);
        await expect(
          this.batcher.dispatchBatchCallback(1, BigInt(this.abiEncodedClearValues) + 1n, this.decryptionProof),
        ).to.be.reverted;
      });

      it('should succeed if unwrap already finalized', async function () {
        await this.fromToken.finalizeUnwrap(this.unwrapAmount, this.abiEncodedClearValues, this.decryptionProof);
        await this.batcher.dispatchBatchCallback(this.batchId, this.abiEncodedClearValues, this.decryptionProof);
      });
    });

    describe('dispatchBatch', function () {
      beforeEach(async function () {
        this.batchId = await this.batcher.currentBatchId();

        await this.batcher.join(1000);
      });

      it('should emit event', async function () {
        await expect(this.batcher.dispatchBatch()).to.emit(this.batcher, 'BatchDispatched').withArgs(this.batchId);
      });
    });
  });
});
