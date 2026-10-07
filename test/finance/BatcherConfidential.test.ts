import { BatcherConfidentialSwapMock } from '../../types';
import { $ERC20Mock } from '../../types/contracts-exposed/mocks/token/ERC20Mock.sol/$ERC20Mock';
import { $ERC7984ERC20Wrapper } from '../../types/contracts-exposed/token/ERC7984/extensions/ERC7984ERC20Wrapper.sol/$ERC7984ERC20Wrapper';
import { FhevmType } from '@fhevm/hardhat-plugin';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import { expect } from 'chai';
import { EventLog } from 'ethers';
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
  Settling,
  Finalized,
  Failed,
}

enum RouteMode {
  Swap,
  Send,
  Revert,
  KeepInput,
  SendAndReceive,
  BurnGasThenSwap,
}

// Dispatches the current batch and returns the arguments of its callback.
async function dispatch(batcher: BatcherConfidentialSwapMock) {
  const batchId = await batcher.currentBatchId();
  await batcher.dispatchBatch();
  const { abiEncodedClearValues, decryptionProof } = await fhevm.publicDecrypt([
    await batcher.unwrapRequestId(batchId),
  ]);
  return { batchId, abiEncodedClearValues, decryptionProof };
}

// Helper to encode batch state as bitmap (mirrors _encodeStateBitmap in contract)
function encodeStateBitmap(...states: BatchState[]): bigint {
  return states.reduce((acc, state) => acc | (1n << BigInt(state)), 0n);
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

    const exchange = await ethers.deployContract('$ExchangeMock', [
      fromTokenUnderlying,
      toTokenUnderlying,
      ethers.parseEther('1'),
    ]);

    await Promise.all(
      [fromTokenUnderlying, toTokenUnderlying].map(async token => {
        await token.$_mint(exchange, ethers.parseEther('1000'));
      }),
    );

    const batcher = await ethers.deployContract('$BatcherConfidentialSwapMock', [
      fromToken,
      toToken,
      exchange,
      operator,
    ]);

    for (const approver of [holder, recipient]) {
      await fromToken.connect(approver).setOperator(batcher, 2n ** 48n - 1n);
    }

    Object.assign(this, {
      exchange,
      batcher,
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

  it('should reject different wrappers with the same underlying', async function () {
    const anotherWrapper = await ethers.deployContract('$ERC7984ERC20WrapperMock', [
      this.fromTokenUnderlying,
      name,
      symbol,
      uri,
    ]);

    await expect(
      ethers.deployContract('$BatcherConfidentialSwapMock', [
        this.fromToken,
        anotherWrapper,
        this.exchange,
        this.operator,
      ]),
    ).to.be.revertedWithCustomError(this.batcher, 'DuplicateUnderlyingTokens');
  });

  it('should reject invalid fromToken', async function () {
    const confidentialToken = await ethers.deployContract('$ERC7984Mock', ['Mock Token', 'MTK', 'URI']);

    await expect(
      ethers.deployContract('$BatcherConfidentialSwapMock', [
        confidentialToken,
        this.toToken,
        this.exchange,
        this.operator,
      ]),
    )
      .to.be.revertedWithCustomError(this.batcher, 'InvalidWrapperToken')
      .withArgs(confidentialToken.target);
  });

  it('should reject invalid toToken', async function () {
    const confidentialToken = await ethers.deployContract('$ERC7984Mock', ['Mock Token', 'MTK', 'URI']);

    await expect(
      ethers.deployContract('$BatcherConfidentialSwapMock', [
        this.fromToken,
        confidentialToken,
        this.exchange,
        this.operator,
      ]),
    )
      .to.be.revertedWithCustomError(this.batcher, 'InvalidWrapperToken')
      .withArgs(confidentialToken.target);
  });

  for (const viaCallback of [true, false]) {
    describe(`join ${viaCallback ? 'via callback' : 'directly'}`, async function () {
      const join = async function (
        token: $ERC7984ERC20Wrapper,
        sender: HardhatEthersSigner,
        batcher: BatcherConfidentialSwapMock,
        amount: bigint,
      ) {
        if (viaCallback) {
          const encryptedInput = await fhevm
            .createEncryptedInput(token.target.toString(), sender.address)
            .add64(amount)
            .encrypt();

          return token
            .connect(sender)
            ['confidentialTransferAndCall(address,bytes32,bytes,bytes)'](
              batcher,
              encryptedInput.handles[0],
              encryptedInput.inputProof,
              ethers.ZeroHash,
            );
        } else {
          return batcher.connect(sender)['join(uint64)'](amount);
        }
      };

      it('should increase individual deposits', async function () {
        const batchId = await this.batcher.currentBatchId();

        await expect(this.batcher.deposits(batchId, this.holder)).to.eventually.eq(ethers.ZeroHash);

        await join(this.fromToken, this.holder, this.batcher, 1000n);

        await expect(
          fhevm.userDecryptEuint(
            FhevmType.euint64,
            await this.batcher.deposits(batchId, this.holder),
            this.batcher,
            this.holder,
          ),
        ).to.eventually.eq('1000');

        await join(this.fromToken, this.holder, this.batcher, 2000n);

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
        await join(this.fromToken, this.holder, this.batcher, 1000n);
        await join(this.fromToken, this.recipient, this.batcher, 2000n);

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

        await expect(join(this.fromToken, this.holder, this.batcher, 1000n))
          .to.emit(this.batcher, 'Joined')
          .withArgs(batchId, this.holder.address, anyValue);
      });

      it('should be able to decrypt joined amount', async function () {
        const tx = await join(this.fromToken, this.holder, this.batcher, 1000n);
        const event = (await tx.wait().then(tx => tx!.logs.filter(log => log.address === this.batcher.target)))[0];
        const joinedAmount = (event as EventLog).data;

        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, joinedAmount, this.batcher, this.holder),
        ).to.eventually.eq('1000');
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

      if (viaCallback) {
        it('must come from the token', async function () {
          await expect(
            this.batcher.onConfidentialTransferReceived(ethers.ZeroAddress, this.holder, ethers.ZeroHash, '0x'),
          ).to.be.revertedWithCustomError(this.batcher, 'Unauthorized');
        });
      }
    });
  }

  const balanceOf = async (token: $ERC7984ERC20Wrapper, account: HardhatEthersSigner) =>
    BigInt(await fhevm.userDecryptEuint(FhevmType.euint64, await token.confidentialBalanceOf(account), token, account));

  describe('claim', function () {
    beforeEach(async function () {
      await this.batcher.join(1000);
      const { batchId, abiEncodedClearValues, decryptionProof } = await dispatch(this.batcher);
      await this.batcher.dispatchBatchCallback(batchId, abiEncodedClearValues, decryptionProof);

      this.batchId = batchId;
      this.exchangeRate = BigInt(await this.batcher.exchangeRate(this.batchId));
      this.deposit = 1000n;
    });

    it('should clear deposits', async function () {
      await this.batcher.claim(this.batchId, this.holder);

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
      const before = await balanceOf(this.toToken, this.holder);

      await this.batcher.claim(this.batchId, this.holder);

      await expect(balanceOf(this.toToken, this.holder)).to.eventually.eq(
        before + (this.exchangeRate * this.deposit) / exchangeRateMantissa,
      );
    });

    it('should revert if not finalized', async function () {
      const currentBatchId = await this.batcher.currentBatchId();
      await expect(this.batcher.claim(currentBatchId, this.holder))
        .to.be.revertedWithCustomError(this.batcher, 'BatchUnexpectedState')
        .withArgs(currentBatchId, BatchState.Pending, encodeStateBitmap(BatchState.Finalized));
    });

    it('should revert if account did not participate in the batch', async function () {
      await expect(this.batcher.claim(this.batchId, this.recipient))
        .to.be.revertedWithCustomError(this.batcher, 'ZeroDeposits')
        .withArgs(this.batchId, this.recipient.address);
    });

    it('should emit event', async function () {
      await expect(this.batcher.claim(this.batchId, this.holder))
        .to.emit(this.batcher, 'Claimed')
        .withArgs(this.batchId, this.holder.address, anyValue, anyValue);
    });

    it('should allow retry claim (idempotent when fully claimed)', async function () {
      await this.batcher.claim(this.batchId, this.holder);
      await expect(this.batcher.claim(this.batchId, this.holder)).to.emit(this.batcher, 'Claimed');

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
      // will burn `toToken` from batcher to induce failed transfer
      await this.toToken['$_burn(address,uint64)'](this.batcher, 100n);

      let claimEvent = (await (await this.batcher.claim(this.batchId, this.holder)).wait()).logs.filter(
        (log: any) => log.address === this.batcher.target,
      )[0];

      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, claimEvent.args[2], this.toToken.target, this.holder),
      ).to.eventually.eq(0);

      await this.toToken['$_mint(address,uint64)'](this.batcher, 100n);

      claimEvent = (await (await this.batcher.claim(this.batchId, this.holder)).wait()).logs.filter(
        (log: any) => log.address === this.batcher.target,
      )[0];

      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, claimEvent.args[2], this.toToken.target, this.holder),
      ).to.eventually.eq(1000n);
    });

    describe('on behalf of (relayer)', function () {
      it('should send tokens to the depositor, not the relayer', async function () {
        const before = await balanceOf(this.toToken, this.holder);

        await this.batcher.connect(this.operator).claim(this.batchId, this.holder);

        await expect(balanceOf(this.toToken, this.holder)).to.eventually.eq(
          before + (this.exchangeRate * this.deposit) / exchangeRateMantissa,
        );
      });

      it('should emit event with the depositor address', async function () {
        await expect(this.batcher.connect(this.operator).claim(this.batchId, this.holder))
          .to.emit(this.batcher, 'Claimed')
          .withArgs(this.batchId, this.holder.address, anyValue, anyValue);
      });
    });
  });

  describe('quit', function () {
    beforeEach(async function () {
      this.batchId = await this.batcher.currentBatchId();
      this.deposit = 1000n;

      await this.batcher.join(this.deposit);
    });

    it('should send back full deposit', async function () {
      const before = await balanceOf(this.fromToken, this.holder);

      await this.batcher.quit(this.batchId);

      await expect(balanceOf(this.fromToken, this.holder)).to.eventually.eq(before + this.deposit);
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
      await this.batcher.dispatchBatch();

      await expect(this.batcher.quit(this.batchId))
        .to.be.revertedWithCustomError(this.batcher, 'BatchUnexpectedState')
        .withArgs(this.batchId, BatchState.Dispatched, encodeStateBitmap(BatchState.Pending, BatchState.Failed));
    });

    it('should revert if caller did not participate in the batch', async function () {
      await expect(this.batcher.connect(this.recipient).quit(this.batchId))
        .to.be.revertedWithCustomError(this.batcher, 'ZeroDeposits')
        .withArgs(this.batchId, this.recipient.address);
    });

    it('should emit event', async function () {
      await expect(this.batcher.quit(this.batchId))
        .to.emit(this.batcher, 'Quit')
        .withArgs(this.batchId, this.holder.address, anyValue);
    });

    describe('on behalf of', function () {
      it('should send tokens to the depositor, not the caller', async function () {
        const before = await balanceOf(this.fromToken, this.holder);

        await this.batcher.connect(this.operator)['$_quit(uint256,address)'](this.batchId, this.holder);

        await expect(balanceOf(this.fromToken, this.holder)).to.eventually.eq(before + this.deposit);
      });

      it('should emit event with the depositor address', async function () {
        await expect(this.batcher.connect(this.operator)['$_quit(uint256,address)'](this.batchId, this.holder))
          .to.emit(this.batcher, 'Quit')
          .withArgs(this.batchId, this.holder.address, anyValue);
      });
    });
  });

  describe('dispatchBatchCallback', function () {
    beforeEach(async function () {
      this.joinAmount = 1000n;
      await this.batcher.join(this.joinAmount);
      Object.assign(this, await dispatch(this.batcher));
      this.callback = () =>
        this.batcher.dispatchBatchCallback(this.batchId, this.abiEncodedClearValues, this.decryptionProof);
    });

    it('should finalize unwrap', async function () {
      const unwrapRequestId = await this.batcher.unwrapRequestId(this.batchId);
      await expect(this.callback())
        .to.emit(this.fromToken, 'UnwrapFinalized')
        .withArgs(this.batcher, unwrapRequestId, unwrapRequestId, this.abiEncodedClearValues);
    });

    it('should revert if proof validation fails', async function () {
      const unwrapRequestId = await this.batcher.unwrapRequestId(this.batchId);
      await this.fromToken.finalizeUnwrap(unwrapRequestId, this.abiEncodedClearValues, this.decryptionProof);
      await expect(
        this.batcher.dispatchBatchCallback(this.batchId, BigInt(this.abiEncodedClearValues) + 1n, this.decryptionProof),
      ).to.be.reverted;
    });

    it('should succeed if unwrap already finalized', async function () {
      const unwrapRequestId = await this.batcher.unwrapRequestId(this.batchId);
      await this.fromToken.finalizeUnwrap(unwrapRequestId, this.abiEncodedClearValues, this.decryptionProof);
      await expect(this.callback()).to.emit(this.batcher, 'BatchFinalized');
    });

    describe('when the route receives its outcome', function () {
      it('should finalize with the swap rate and no refund', async function () {
        await expect(this.callback())
          .to.emit(this.batcher, 'BatchFinalized')
          .withArgs(this.batchId, exchangeRateMantissa, 0n);
      });

      it('should revert if nothing is received', async function () {
        await this.exchange.setExchangeRate(0);

        await expect(this.callback())
          .to.be.revertedWithCustomError(this.batcher, 'InvalidExchangeRate')
          .withArgs(this.batchId, this.joinAmount, 0, 0);
      });
    });

    describe('when the route sends the input out', function () {
      beforeEach(async function () {
        await this.batcher.setRouteMode(RouteMode.Send);
      });

      it('should move the batch to settling', async function () {
        await expect(this.callback()).to.emit(this.batcher, 'BatchSettling').withArgs(this.batchId);
      });

      it('should revert if the route keeps the input', async function () {
        await this.batcher.setRouteMode(RouteMode.KeepInput);

        await expect(this.callback())
          .to.be.revertedWithCustomError(this.batcher, 'UnspentInput')
          .withArgs(this.batchId);
      });

      it('should revert if the route receives toToken without reporting the outcome', async function () {
        await this.batcher.setRouteMode(RouteMode.SendAndReceive);

        await expect(this.callback())
          .to.be.revertedWithCustomError(this.batcher, 'IntermediateStepBalanceChanged')
          .withArgs(this.batchId);
      });
    });

    describe('when the route reverts', function () {
      beforeEach(async function () {
        await this.batcher.setRouteMode(RouteMode.Revert);
      });

      it('should mark the batch failed', async function () {
        await expect(this.callback()).to.emit(this.batcher, 'BatchFailed').withArgs(this.batchId, anyValue);
      });

      it('should rewrap the whole input', async function () {
        await expect(this.callback())
          .to.emit(this.fromTokenUnderlying, 'Transfer')
          .withArgs(this.fromToken, this.batcher, this.joinAmount * this.fromTokenRate) // unwrap
          .to.emit(this.fromTokenUnderlying, 'Transfer')
          .withArgs(this.batcher, this.fromToken, this.joinAmount * this.fromTokenRate); // rewrap
      });

      it('should release the in-flight slot', async function () {
        await this.callback();

        await expect(this.batcher.inFlightBatchId()).to.eventually.eq(0);
      });
    });

    it('should revert if sent with too little gas to give the route its full budget', async function () {
      // Below the route's 3M budget plus the failure reserve.
      await expect(
        this.batcher.dispatchBatchCallback(this.batchId, this.abiEncodedClearValues, this.decryptionProof, {
          gasLimit: 3_000_000n,
        }),
      )
        .to.be.revertedWithCustomError(this.batcher, 'InsufficientRouteGas')
        .withArgs(this.batchId);
    });

    it('should fail the batch when the route needs more than its gas limit', async function () {
      await this.batcher.setRouteMode(RouteMode.BurnGasThenSwap);
      await this.batcher.setRouteGasLimit(1_000_000);

      await expect(this.callback()).to.emit(this.batcher, 'BatchFailed').withArgs(this.batchId, '0x');
    });

    it('should finalize with zero rates if unwrap amount is 0', async function () {
      await this.callback();
      const empty = await dispatch(this.batcher);

      await expect(
        this.batcher.dispatchBatchCallback(empty.batchId, empty.abiEncodedClearValues, empty.decryptionProof),
      )
        .to.emit(this.batcher, 'BatchFinalized')
        .withArgs(empty.batchId, 0n, 0n);
    });
  });

  describe('settleBatch', function () {
    beforeEach(async function () {
      this.joinAmount = 1000n;
      await this.batcher.join(this.joinAmount);
      const { batchId, abiEncodedClearValues, decryptionProof } = await dispatch(this.batcher);
      await this.batcher.setRouteMode(RouteMode.Send);
      await this.batcher.dispatchBatchCallback(batchId, abiEncodedClearValues, decryptionProof);

      this.batchId = batchId;
      this.rawAmount = this.joinAmount * this.fromTokenRate;
    });

    it('should keep the batch settling until the outcome is received', async function () {
      await this.batcher.settleBatch(this.batchId);

      await expect(this.batcher.batchState(this.batchId)).to.eventually.eq(BatchState.Settling);
    });

    it('should revert if a step receives toToken without reporting the outcome', async function () {
      await this.batcher.setSettleReceivesToToken(true);

      await expect(this.batcher.settleBatch(this.batchId))
        .to.be.revertedWithCustomError(this.batcher, 'IntermediateStepBalanceChanged')
        .withArgs(this.batchId);
    });

    it('should finalize on a fill', async function () {
      await this.toTokenUnderlying.$_mint(this.batcher, this.rawAmount);
      await this.batcher.setOutcomeReceived(true);

      await expect(this.batcher.settleBatch(this.batchId))
        .to.emit(this.batcher, 'BatchFinalized')
        .withArgs(this.batchId, exchangeRateMantissa, 0n);
    });

    it('should finalize on a full return', async function () {
      await this.fromTokenUnderlying.$_mint(this.batcher, this.rawAmount);
      await this.batcher.setOutcomeReceived(true);

      await expect(this.batcher.settleBatch(this.batchId))
        .to.emit(this.batcher, 'BatchFinalized')
        .withArgs(this.batchId, 0n, exchangeRateMantissa);
    });

    it('should finalize on a partial fill with both rates', async function () {
      await this.toTokenUnderlying.$_mint(this.batcher, this.rawAmount / 4n);
      await this.fromTokenUnderlying.$_mint(this.batcher, (this.rawAmount * 3n) / 4n);
      await this.batcher.setOutcomeReceived(true);

      await expect(this.batcher.settleBatch(this.batchId))
        .to.emit(this.batcher, 'BatchFinalized')
        .withArgs(this.batchId, exchangeRateMantissa / 4n, (exchangeRateMantissa * 3n) / 4n);
    });

    it('should pay both tokens on claim after a partial fill', async function () {
      await this.toTokenUnderlying.$_mint(this.batcher, this.rawAmount / 4n);
      await this.fromTokenUnderlying.$_mint(this.batcher, (this.rawAmount * 3n) / 4n);
      await this.batcher.setOutcomeReceived(true);
      await this.batcher.settleBatch(this.batchId);
      const fromBefore = await balanceOf(this.fromToken, this.holder);

      await this.batcher.claim(this.batchId, this.holder);

      await expect(balanceOf(this.fromToken, this.holder)).to.eventually.eq(fromBefore + (this.joinAmount * 3n) / 4n);
    });

    it('should refund in full when a return comes with a dust donation of toToken', async function () {
      // The case a route cannot classify: the input came back, and someone sent a few units of toToken.
      await this.fromTokenUnderlying.$_mint(this.batcher, this.rawAmount);
      await this.toTokenUnderlying.$_mint(this.batcher, this.toTokenRate);
      await this.batcher.setOutcomeReceived(true);
      await this.batcher.settleBatch(this.batchId);
      const fromBefore = await balanceOf(this.fromToken, this.holder);

      await this.batcher.claim(this.batchId, this.holder);

      await expect(balanceOf(this.fromToken, this.holder)).to.eventually.eq(fromBefore + this.joinAmount);
    });

    it('should revert if nothing was received', async function () {
      await this.batcher.setOutcomeReceived(true);

      await expect(this.batcher.settleBatch(this.batchId))
        .to.be.revertedWithCustomError(this.batcher, 'InvalidExchangeRate')
        .withArgs(this.batchId, this.joinAmount, 0, 0);
    });

    it('should revert if the batch is not settling', async function () {
      const currentBatchId = await this.batcher.currentBatchId();

      await expect(this.batcher.settleBatch(currentBatchId))
        .to.be.revertedWithCustomError(this.batcher, 'BatchUnexpectedState')
        .withArgs(currentBatchId, BatchState.Pending, encodeStateBitmap(BatchState.Settling));
    });
  });

  describe('dispatchBatch', function () {
    it('should emit event', async function () {
      const batchId = await this.batcher.currentBatchId();
      await this.batcher.join(1000);

      await expect(this.batcher.dispatchBatch()).to.emit(this.batcher, 'BatchDispatched').withArgs(batchId);
    });

    it('should dispatch with an unwrap amount of zero', async function () {
      const { abiEncodedClearValues } = await dispatch(this.batcher);

      expect(BigInt(abiEncodedClearValues)).to.eq(0n);
    });

    it('should revert while another batch is in flight', async function () {
      const { batchId } = await dispatch(this.batcher);

      await expect(this.batcher.dispatchBatch())
        .to.be.revertedWithCustomError(this.batcher, 'BatchInFlight')
        .withArgs(batchId);
    });

    it('should succeed once the batch in flight is finalized', async function () {
      await this.batcher.join(1000);
      const { batchId, abiEncodedClearValues, decryptionProof } = await dispatch(this.batcher);
      await this.batcher.dispatchBatchCallback(batchId, abiEncodedClearValues, decryptionProof);

      await expect(this.batcher.dispatchBatch()).to.emit(this.batcher, 'BatchDispatched');
    });
  });

  describe('redispatchBatch', function () {
    beforeEach(async function () {
      await this.batcher.join(1000);
      const { batchId, abiEncodedClearValues, decryptionProof } = await dispatch(this.batcher);
      await this.batcher.setRouteMode(RouteMode.Revert);
      await this.batcher.dispatchBatchCallback(batchId, abiEncodedClearValues, decryptionProof);
      await this.batcher.setRouteMode(RouteMode.Swap);
      this.batchId = batchId;
    });

    it('should dispatch the failed batch again', async function () {
      await expect(this.batcher.redispatchBatch(this.batchId))
        .to.emit(this.batcher, 'BatchDispatched')
        .withArgs(this.batchId);
    });

    it('should finalize the failed batch on its next callback', async function () {
      await this.batcher.redispatchBatch(this.batchId);
      const { abiEncodedClearValues, decryptionProof } = await fhevm.publicDecrypt([
        await this.batcher.unwrapRequestId(this.batchId),
      ]);

      await expect(this.batcher.dispatchBatchCallback(this.batchId, abiEncodedClearValues, decryptionProof))
        .to.emit(this.batcher, 'BatchFinalized')
        .withArgs(this.batchId, exchangeRateMantissa, 0n);
    });

    it('should let depositors quit the failed batch', async function () {
      const before = await balanceOf(this.fromToken, this.holder);

      await this.batcher.quit(this.batchId);

      await expect(balanceOf(this.fromToken, this.holder)).to.eventually.eq(before + 1000n);
    });

    it('should revert for a batch that has not failed', async function () {
      const currentBatchId = await this.batcher.currentBatchId();

      await expect(this.batcher.redispatchBatch(currentBatchId))
        .to.be.revertedWithCustomError(this.batcher, 'BatchUnexpectedState')
        .withArgs(currentBatchId, BatchState.Pending, encodeStateBitmap(BatchState.Failed));
    });
  });

  describe('batch state', async function () {
    beforeEach(async function () {
      await this.batcher.join(1000n);
      Object.assign(this, await dispatch(this.batcher));
      this.callback = () =>
        this.batcher.dispatchBatchCallback(this.batchId, this.abiEncodedClearValues, this.decryptionProof);
    });

    it('should revert if batch does not exist', async function () {
      const nonExistentBatchId = this.batchId + 2n;
      await expect(this.batcher.batchState(nonExistentBatchId))
        .to.be.revertedWithCustomError(this.batcher, 'BatchNonexistent')
        .withArgs(nonExistentBatchId);
    });

    it('should return pending if pending', async function () {
      await expect(this.batcher.batchState(this.batchId + 1n)).to.eventually.eq(BatchState.Pending);
    });

    it('should return dispatched if dispatched', async function () {
      await expect(this.batcher.batchState(this.batchId)).to.eventually.eq(BatchState.Dispatched);
    });

    it('should return settling if settling', async function () {
      await this.batcher.setRouteMode(RouteMode.Send);
      await this.callback();

      await expect(this.batcher.batchState(this.batchId)).to.eventually.eq(BatchState.Settling);
    });

    it('should return finalized if finalized', async function () {
      await this.callback();

      await expect(this.batcher.batchState(this.batchId)).to.eventually.eq(BatchState.Finalized);
    });

    it('should return failed if failed', async function () {
      await this.batcher.setRouteMode(RouteMode.Revert);
      await this.callback();

      await expect(this.batcher.batchState(this.batchId)).to.eventually.eq(BatchState.Failed);
    });
  });

  it('only the batcher can execute the route', async function () {
    await expect(this.batcher.executeRoute(1, 1)).to.be.revertedWithCustomError(this.batcher, 'Unauthorized');
  });
});
