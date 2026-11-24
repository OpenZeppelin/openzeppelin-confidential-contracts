import { getAcl } from '../../helpers/acl';
import { MAX_UINT48 } from '../../helpers/constants';
import { callAndGetResult, callAndGetResults } from '../../helpers/event';
import { INTERFACE_IDS, INVALID_ID } from '../../helpers/interface';
import { product } from '../../helpers/iterate';
import { generators as random } from '../../helpers/random';
import { FhevmType } from '@fhevm/hardhat-plugin';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

const amountToMint = 1000n;

const encryptedAmount = (contract: any, user: any, amount: any) =>
  fhevm.createEncryptedInput(contract.target, user.address).add64(amount).encrypt();

// Shared behavior for ERC7984 tokens. Callers must deploy `this.token`. Holder (account[0]) must not be
// minted more than 1000 tokens.
export function shouldBehaveLikeERC7984(name: string, symbol: string, uri: string, decimals: number, opts: any = {}) {
  describe('behaves like ERC7984', function () {
    beforeEach(async function () {
      const accounts = await ethers.getSigners();
      [this.holder, this.recipient, this.operator, this.anyone] = accounts;

      // standardize holder initial balance to 1000
      expect(opts.holderInitialBalance ?? 0n).to.be.at.most(amountToMint);
      await this.token.$_mint(this.holder, amountToMint - BigInt(opts.holderInitialBalance ?? 0));

      // User decryption requires both the user and the token to be persistently allowed on the handle
      this.acl = await getAcl();
    });

    describe('constructor', function () {
      it('sets the name', async function () {
        await expect(this.token.name()).to.eventually.equal(name);
      });

      it('sets the symbol', async function () {
        await expect(this.token.symbol()).to.eventually.equal(symbol);
      });

      it('sets the uri', async function () {
        await expect(this.token.contractURI()).to.eventually.equal(uri);
      });

      it('sets the decimals', async function () {
        await expect(this.token.decimals()).to.eventually.equal(decimals);
      });
    });

    describe('ERC165', function () {
      it('should support interface', async function () {
        await expect(this.token.supportsInterface(INTERFACE_IDS.ERC7984)).to.eventually.be.true;
        await expect(this.token.supportsInterface(INTERFACE_IDS.ERC7984ERC20Wrapper)).to.eventually.equal(
          !!opts.supportsERC7984ERC20Wrapper,
        );
        await expect(this.token.supportsInterface(INTERFACE_IDS.ERC7984RWA)).to.eventually.equal(
          !!opts.supportsERC7984RWA,
        );
      });

      it('should not support interface', async function () {
        await expect(this.token.supportsInterface(INVALID_ID)).to.eventually.be.false;
      });
    });

    describe('confidentialBalanceOf', function () {
      it('handle can be decrypted by owner', async function () {
        const balanceOfHandleHolder = await this.token.confidentialBalanceOf(this.holder);
        await expect(this.acl.persistAllowed(balanceOfHandleHolder, this.token)).to.eventually.be.true;
        await expect(this.acl.persistAllowed(balanceOfHandleHolder, this.holder)).to.eventually.be.true;
      });

      it('handle cannot be decrypted by non-owner', async function () {
        const balanceOfHandleHolder = await this.token.confidentialBalanceOf(this.holder);
        await expect(this.acl.persistAllowed(balanceOfHandleHolder, this.anyone)).to.eventually.be.false;
      });
    });

    describe('setOperator', function () {
      it('sets the operator', async function () {
        const timestamp = (await ethers.provider.getBlock('latest'))!.timestamp + 100;

        await expect(this.token.connect(this.holder).setOperator(this.operator, timestamp))
          .to.emit(this.token, 'OperatorSet')
          .withArgs(this.holder.address, this.operator.address, timestamp);

        await expect(this.token.isOperator(this.holder, this.operator)).to.eventually.be.true;
      });

      it('holder is its own operator', async function () {
        await expect(this.token.isOperator(this.holder, this.holder)).to.eventually.be.true;
      });

      it('reverts when holder is the operator', async function () {
        const timestamp = (await ethers.provider.getBlock('latest'))!.timestamp + 100;

        await expect(this.token.connect(this.holder).setOperator(this.holder, timestamp))
          .to.be.revertedWithCustomError(this.token, 'ERC7984InvalidOperator')
          .withArgs(this.holder.address);
      });

      it('reverts when operator is the zero address', async function () {
        await expect(this.token.connect(this.holder).setOperator(ethers.ZeroAddress, 0))
          .to.be.revertedWithCustomError(this.token, 'ERC7984InvalidOperator')
          .withArgs(ethers.ZeroAddress);
      });
    });

    describe('transfer', function () {
      for (const [operator, callback, memo] of product(
        [undefined, 'self', 'operator'], // operator. this[self] is undefined so sender falls back to from in {callTransfer}
        [undefined, '0x'], // callback
        [undefined, random.bytes32()], // memo
      )) {
        const fnName = ['confidentialTransfer', operator && 'From', callback && 'AndCall'].filter(Boolean).join('');

        // An empty input proof makes the token use `amount` as an existing handle the sender must be allowed to use.
        const callTransfer = (
          contract: any,
          from: any,
          to: any,
          amount: any,
          sender: any = from,
          callbackData = callback,
        ) =>
          contract.connect(sender)[fnName](
            ...[
              operator && from,
              to,
              amount.handles?.[0] ?? amount,
              ethers.Typed.bytes(amount.inputProof ?? '0x'), // input proof
              callbackData && ethers.Typed.bytes(callbackData), // callback data
              memo && ethers.Typed.bytes32(memo),
            ].filter(Boolean),
          );

        describe(`${fnName} - called by ${
          operator == 'operator' ? 'operator' : 'sender'
        }, callback: ${!!callback}, memo: ${!!memo}`, function () {
          beforeEach(async function () {
            if (operator === 'operator') {
              await this.token.connect(this.holder).setOperator(this.operator, MAX_UINT48);
            }
          });

          for (const sufficientBalance of [true, false]) {
            it(`${sufficientBalance ? 'sufficient' : 'insufficient'} balance`, async function () {
              const amount = sufficientBalance ? 100n : 1_000_000n;
              const eamount = await encryptedAmount(this.token, this[operator] ?? this.holder, amount);

              const txPromise = callTransfer(this.token, this.holder, this.recipient, eamount, this[operator]);
              await expect(txPromise)
                .to.emit(this.token, 'ConfidentialTransfer')
                .withArgs(this.holder, this.recipient, anyValue, memo ?? ethers.ZeroHash);
              await expect(txPromise).to.changeConfidentialBalances(
                this.token,
                [this.holder, this.recipient],
                sufficientBalance ? [-amount, amount] : [0n, 0n],
              );

              const [from, to, transferAmountHandle] = await callAndGetResult(txPromise, 'ConfidentialTransfer');
              expect(from).to.equal(this.holder.address);
              expect(to).to.equal(this.recipient.address);

              await expect(fhevm.debugger.decryptEuint(FhevmType.euint64, transferAmountHandle)).to.eventually.equal(
                sufficientBalance ? amount : 0n,
              );

              await expect(this.acl.persistAllowed(transferAmountHandle, this.token)).to.eventually.be.true;
              await expect(this.acl.persistAllowed(transferAmountHandle, this.holder)).to.eventually.be.true;
              await expect(this.acl.persistAllowed(transferAmountHandle, this.recipient)).to.eventually.be.true;
              // Other can not reencrypt the transfer amount
              await expect(this.acl.persistAllowed(transferAmountHandle, this.operator)).to.eventually.be.false;

              const holderBalanceHandle = await this.token.confidentialBalanceOf(this.holder);
              await expect(this.acl.persistAllowed(holderBalanceHandle, this.token)).to.eventually.be.true;
              await expect(this.acl.persistAllowed(holderBalanceHandle, this.holder)).to.eventually.be.true;

              const recipientBalanceHandle = await this.token.confidentialBalanceOf(this.recipient);
              await expect(this.acl.persistAllowed(recipientBalanceHandle, this.token)).to.eventually.be.true;
              await expect(this.acl.persistAllowed(recipientBalanceHandle, this.recipient)).to.eventually.be.true;
            });
          }

          operator === 'operator' &&
            it('fails without operator approval', async function () {
              const amount = await encryptedAmount(this.token, this.anyone, 100n);
              await expect(callTransfer(this.token, this.holder, this.recipient, amount, this.anyone))
                .to.be.revertedWithCustomError(this.token, 'ERC7984UnauthorizedSpender')
                .withArgs(this.holder, this.anyone);
            });

          it('from address with no balance', async function () {
            if (operator === 'operator') {
              await this.token.connect(this.anyone).setOperator(this.operator, MAX_UINT48);
            }

            const eamount = await encryptedAmount(this.token, this[operator] ?? this.anyone, 100n);
            const txPromise = callTransfer(this.token, this.anyone, this.recipient, eamount, this[operator]);

            await expect(txPromise)
              .to.emit(this.token, 'ConfidentialTransfer')
              .withArgs(this.anyone, this.recipient, anyValue, memo ?? ethers.ZeroHash);
            await expect(txPromise).to.changeConfidentialBalances(this.token, [this.anyone, this.recipient], [0n, 0n]);
          });

          it('to zero address', async function () {
            const eamount = await encryptedAmount(this.token, this[operator] ?? this.holder, 0n);

            await expect(callTransfer(this.token, this.holder, ethers.ZeroAddress, eamount, this[operator]))
              .to.be.revertedWithCustomError(this.token, 'ERC7984InvalidReceiver')
              .withArgs(ethers.ZeroAddress);
          });

          operator !== 'operator' &&
            it('full balance', async function () {
              const fullBalanceHandle = await this.token.confidentialBalanceOf(this.holder);

              await expect(
                callTransfer(this.token, this.holder, this.recipient, fullBalanceHandle),
              ).to.changeConfidentialBalances(this.token, [this.holder, this.recipient], [-1000n, 1000n]);
            });

          it('other user balance should revert', async function () {
            await this.token.$_mint(this.recipient, 100n);

            const recipientBalanceHandle = await this.token.confidentialBalanceOf(this.recipient);
            await expect(callTransfer(this.token, this.holder, this.recipient, recipientBalanceHandle, this[operator]))
              .to.be.revertedWithCustomError(this.token, 'SenderNotAllowedToUseHandle')
              .withArgs(recipientBalanceHandle, this[operator] ?? this.holder);
          });

          callback &&
            describe('with callback', function () {
              beforeEach(async function () {
                this.recipientContract = await ethers.deployContract('ERC7984ReceiverMock');
              });

              it('refund does not carry the memo', async function () {
                const eamount = await encryptedAmount(this.token, this[operator] ?? this.holder, 100n);

                await expect(callTransfer(this.token, this.holder, this.recipient, eamount, this[operator]))
                  .to.emit(this.token, 'ConfidentialTransfer')
                  .withArgs(this.holder, this.recipient, anyValue, memo ?? ethers.ZeroHash)
                  .to.emit(this.token, 'ConfidentialTransfer')
                  .withArgs(this.recipient, this.holder, anyValue, ethers.ZeroHash);
              });

              for (const callbackSuccess of [false, true]) {
                it(`with callback running ${callbackSuccess ? 'successfully' : 'unsuccessfully'}`, async function () {
                  const amount = 100n;
                  const eamount = await encryptedAmount(this.token, this[operator] ?? this.holder, amount);

                  const txPromise = callTransfer(
                    this.token,
                    this.holder,
                    this.recipientContract,
                    eamount,
                    this[operator],
                    ethers.AbiCoder.defaultAbiCoder().encode(['bool'], [callbackSuccess]),
                  );
                  await expect(txPromise).to.changeConfidentialBalances(
                    this.token,
                    [this.holder, this.recipientContract],
                    callbackSuccess ? [-amount, amount] : [0n, 0n],
                  );

                  // Verify event contents
                  await expect(txPromise)
                    .to.emit(this.recipientContract, 'ConfidentialTransferCallback')
                    .withArgs(callbackSuccess);
                  const [outboundTransferEvent, inboundTransferEvent] = await callAndGetResults(
                    txPromise,
                    'ConfidentialTransfer',
                  );

                  expect(outboundTransferEvent.from).to.equal(this.holder);
                  expect(outboundTransferEvent.to).to.equal(this.recipientContract);
                  await expect(
                    fhevm.debugger.decryptEuint(FhevmType.euint64, outboundTransferEvent.amount),
                  ).to.eventually.equal(amount);
                  await expect(this.acl.persistAllowed(outboundTransferEvent.amount, this.token)).to.eventually.be.true;
                  await expect(this.acl.persistAllowed(outboundTransferEvent.amount, this.holder)).to.eventually.be
                    .true;

                  expect(inboundTransferEvent.from).to.equal(this.recipientContract);
                  expect(inboundTransferEvent.to).to.equal(this.holder);
                  await expect(
                    fhevm.debugger.decryptEuint(FhevmType.euint64, inboundTransferEvent.amount),
                  ).to.eventually.equal(callbackSuccess ? 0n : amount);
                  await expect(this.acl.persistAllowed(inboundTransferEvent.amount, this.token)).to.eventually.be.true;
                  await expect(this.acl.persistAllowed(inboundTransferEvent.amount, this.holder)).to.eventually.be.true;
                });
              }

              it('with callback returning encrypted value without recipient ACL', async function () {
                const eamount = await encryptedAmount(this.token, this[operator] ?? this.holder, 100n);

                const eboolOwner = await ethers.deployContract('ERC7984UnauthorizedReceiverMock', [this.token.target]);
                await eboolOwner.createReturnValue(true);
                const unauthorizedRetval = await eboolOwner.getReturnValue();

                const maliciousReceiver = await ethers.deployContract('ERC7984UnauthorizedReceiverMock', [
                  this.token.target,
                ]);
                await maliciousReceiver.setReturnValue(unauthorizedRetval);

                await expect(callTransfer(this.token, this.holder, maliciousReceiver, eamount, this[operator]))
                  .to.be.revertedWithCustomError(this.token, 'ERC7984UtilsUnauthorizedUseOfEncryptedAmount')
                  .withArgs(unauthorizedRetval, maliciousReceiver.target);
              });

              it('with callback returning an uninitialized value', async function () {
                const eamount = await encryptedAmount(this.token, this[operator] ?? this.holder, 100n);

                const receiver = await ethers.deployContract('ERC7984UnauthorizedReceiverMock', [this.token.target]);

                await expect(
                  callTransfer(this.token, this.holder, receiver, eamount, this[operator]),
                ).to.changeConfidentialBalances(this.token, [this.holder, receiver], [0n, 0n]);
              });

              it('with callback reverting without a reason', async function () {
                const eamount = await encryptedAmount(this.token, this[operator] ?? this.holder, 100n);

                await expect(
                  callTransfer(
                    this.token,
                    this.holder,
                    this.recipientContract,
                    eamount,
                    this[operator],
                    ethers.AbiCoder.defaultAbiCoder().encode(['uint8'], [3]),
                  ),
                )
                  .to.be.revertedWithCustomError(this.token, 'ERC7984InvalidReceiver')
                  .withArgs(this.recipientContract);
              });

              it('with callback reverting with a custom error', async function () {
                const eamount = await encryptedAmount(this.token, this[operator] ?? this.holder, 100n);

                await expect(
                  callTransfer(
                    this.token,
                    this.holder,
                    this.recipientContract,
                    eamount,
                    this[operator],
                    ethers.AbiCoder.defaultAbiCoder().encode(['uint8'], [2]),
                  ),
                )
                  .to.be.revertedWithCustomError(this.recipientContract, 'InvalidInput')
                  .withArgs(2);
              });

              it('to an EOA', async function () {
                const amount = 100n;
                const eamount = await encryptedAmount(this.token, this[operator] ?? this.holder, amount);

                await expect(
                  callTransfer(this.token, this.holder, this.recipient, eamount, this[operator], '0x'),
                ).to.changeConfidentialBalances(this.token, [this.holder, this.recipient], [-amount, amount]);
              });
            });
        });
      }

      it('internal function reverts on from/to address zero', async function () {
        const encryptedInput = await encryptedAmount(this.token, this.holder, 100n);

        await expect(
          this.token
            .connect(this.holder)
            .$_transfer(ethers.ZeroAddress, this.recipient, encryptedInput.handles[0], encryptedInput.inputProof),
        )
          .to.be.revertedWithCustomError(this.token, 'ERC7984InvalidSender')
          .withArgs(ethers.ZeroAddress);

        await expect(
          this.token
            .connect(this.holder)
            .$_transfer(this.holder, ethers.ZeroAddress, encryptedInput.handles[0], encryptedInput.inputProof),
        )
          .to.be.revertedWithCustomError(this.token, 'ERC7984InvalidReceiver')
          .withArgs(ethers.ZeroAddress);
      });
    });
  });
}
