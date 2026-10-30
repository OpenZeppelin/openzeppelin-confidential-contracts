import { allowHandle, getAcl } from '../../helpers/acl';
import { UNLIMITED_OPERATOR, setOperator } from '../../helpers/erc7984';
import { INTERFACE_IDS, INVALID_ID } from '../../helpers/interface';
import { FhevmType } from '@fhevm/hardhat-plugin';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

// Shared behavior for ERC7984 tokens. Callers must deploy `this.token`. Holder (account[0]) must not be
// minted more than 1000 tokens.
function shouldBehaveLikeERC7984(name: string, symbol: string, uri: string, decimals: number, opts: any = {}) {
  describe('behaves like ERC7984', function () {
    beforeEach(async function () {
      const accounts = await ethers.getSigners();
      [this.holder, this.recipient, this.operator, this.anyone] = accounts;

      // standardize holder initial balance to 1000
      let amountToMint = 1000;
      if (!!opts.holderInitialBalance) {
        if (opts.holderInitialBalance > 1000) {
          throw new Error('Holder initial balance cannot be greater than 1000');
        }
        amountToMint -= opts.holderInitialBalance;
      }
      const encryptedInput = await fhevm
        .createEncryptedInput(this.token.target, this.holder.address)
        .add64(amountToMint)
        .encrypt();

      await this.token
        .connect(this.holder)
        ['$_mint(address,bytes32,bytes)'](this.holder, encryptedInput.handles[0], encryptedInput.inputProof);
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
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, balanceOfHandleHolder, await this.token.getAddress(), this.holder),
        ).to.eventually.equal(1000);
      });

      it('handle cannot be decrypted by non-owner', async function () {
        const balanceOfHandleHolder = await this.token.confidentialBalanceOf(this.holder);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, balanceOfHandleHolder, await this.token.getAddress(), this.anyone),
        ).to.be.rejectedWith(generateDecryptionErrorMessage(balanceOfHandleHolder, this.anyone.address));
      });
    });

    describe('setOperator', function () {
      it('sets the operator', async function () {
        const timestamp = (await ethers.provider.getBlock('latest'))!.timestamp + 100;

        await expect(setOperator(this.token, this.holder, this.operator.address, timestamp))
          .to.emit(this.token, 'OperatorSet')
          .withArgs(this.holder.address, this.operator.address, timestamp, UNLIMITED_OPERATOR);

        await expect(this.token.isOperator(this.holder, this.operator)).to.eventually.deep.equal([
          true,
          UNLIMITED_OPERATOR,
        ]);
      });

      it('holder is its own operator', async function () {
        await expect(this.token.isOperator(this.holder, this.holder)).to.eventually.deep.equal([
          true,
          UNLIMITED_OPERATOR,
        ]);
      });

      it('reverts when holder is the operator', async function () {
        const timestamp = (await ethers.provider.getBlock('latest'))!.timestamp + 100;

        await expect(setOperator(this.token, this.holder, this.holder.address, timestamp))
          .to.be.revertedWithCustomError(this.token, 'ERC7984InvalidOperator')
          .withArgs(this.holder.address);
      });

      it('reverts when operator is the zero address', async function () {
        await expect(setOperator(this.token, this.holder, ethers.ZeroAddress, 0))
          .to.be.revertedWithCustomError(this.token, 'ERC7984InvalidOperator')
          .withArgs(ethers.ZeroAddress);
      });
    });

    describe('operator limit', function () {
      const until = 2n ** 48n - 1n;

      // Transfers `amount` from the holder to the recipient, as the operator.
      const transferFrom = async function (this: any, amount: number) {
        const input = await fhevm
          .createEncryptedInput(await this.token.getAddress(), this.operator.address)
          .add64(amount)
          .encrypt();

        return this.token
          .connect(this.operator)
          ['confidentialTransferFrom(address,address,bytes32,bytes)'](
            this.holder,
            this.recipient,
            input.handles[0],
            input.inputProof,
          );
      };

      const decrypt = async function (this: any, handle: string, account: any) {
        return fhevm.userDecryptEuint(FhevmType.euint64, handle, await this.token.getAddress(), account);
      };

      describe('without a limit', function () {
        beforeEach(async function () {
          await setOperator(this.token, this.holder, this.operator.address, until);
        });

        it('registers the unlimited sentinel', async function () {
          await expect(this.token.isOperator(this.holder, this.operator)).to.eventually.deep.equal([
            true,
            UNLIMITED_OPERATOR,
          ]);
        });

        it('does not constrain the operator', async function () {
          await transferFrom.call(this, 600);
          await transferFrom.call(this, 400);

          await expect(
            decrypt.call(this, await this.token.confidentialBalanceOf(this.recipient), this.recipient),
          ).to.eventually.equal(1000);
          await expect(this.token.isOperator(this.holder, this.operator)).to.eventually.deep.equal([
            true,
            UNLIMITED_OPERATOR,
          ]);
        });
      });

      describe('with a limit', function () {
        beforeEach(async function () {
          await setOperator(this.token, this.holder, this.operator.address, until, 300);
        });

        it('limit is decryptable by the holder and the operator', async function () {
          const [, limit] = await this.token.isOperator(this.holder, this.operator);

          await expect(decrypt.call(this, limit, this.holder)).to.eventually.equal(300);
          await expect(decrypt.call(this, limit, this.operator)).to.eventually.equal(300);
          await expect(decrypt.call(this, limit, this.anyone)).to.be.rejectedWith(
            generateDecryptionErrorMessage(limit, this.anyone.address),
          );
        });

        it('a transfer within the limit consumes it', async function () {
          await transferFrom.call(this, 100);

          await expect(
            decrypt.call(this, await this.token.confidentialBalanceOf(this.recipient), this.recipient),
          ).to.eventually.equal(100);

          const [, limit] = await this.token.isOperator(this.holder, this.operator);
          await expect(decrypt.call(this, limit, this.holder)).to.eventually.equal(200);
          await expect(decrypt.call(this, limit, this.operator)).to.eventually.equal(200);
        });

        it('the limit is consumed across transfers', async function () {
          await transferFrom.call(this, 100);
          await transferFrom.call(this, 200);

          await expect(
            decrypt.call(this, await this.token.confidentialBalanceOf(this.recipient), this.recipient),
          ).to.eventually.equal(300);

          const [, limit] = await this.token.isOperator(this.holder, this.operator);
          await expect(decrypt.call(this, limit, this.holder)).to.eventually.equal(0);
        });

        it('a transfer over the limit moves nothing and leaves the limit untouched', async function () {
          await transferFrom.call(this, 301);

          await expect(
            decrypt.call(this, await this.token.confidentialBalanceOf(this.holder), this.holder),
          ).to.eventually.equal(1000);

          const [, limit] = await this.token.isOperator(this.holder, this.operator);
          await expect(decrypt.call(this, limit, this.holder)).to.eventually.equal(300);
        });

        it('a transfer over the holder balance moves nothing and leaves the limit untouched', async function () {
          await setOperator(this.token, this.holder, this.operator.address, until, 1500);

          await transferFrom.call(this, 1200);

          await expect(
            decrypt.call(this, await this.token.confidentialBalanceOf(this.holder), this.holder),
          ).to.eventually.equal(1000);

          const [, limit] = await this.token.isOperator(this.holder, this.operator);
          await expect(decrypt.call(this, limit, this.holder)).to.eventually.equal(1500);
        });

        describe('without input proof', function () {
          // The operator spends the holder's balance handle (1000), which the holder shares with it.
          const transferFromHandle = async function (this: any) {
            const handle = await this.token.confidentialBalanceOf(this.holder);
            await allowHandle(this.holder, this.operator, handle);

            return this.token
              .connect(this.operator)
              ['confidentialTransferFrom(address,address,bytes32)'](this.holder, this.recipient, handle);
          };

          it('a transfer within the limit consumes it', async function () {
            await setOperator(this.token, this.holder, this.operator.address, until, 1200);

            await transferFromHandle.call(this);

            await expect(
              decrypt.call(this, await this.token.confidentialBalanceOf(this.recipient), this.recipient),
            ).to.eventually.equal(1000);

            const [, limit] = await this.token.isOperator(this.holder, this.operator);
            await expect(decrypt.call(this, limit, this.holder)).to.eventually.equal(200);
          });

          it('a transfer over the limit moves nothing and leaves the limit untouched', async function () {
            await transferFromHandle.call(this);

            await expect(
              decrypt.call(this, await this.token.confidentialBalanceOf(this.holder), this.holder),
            ).to.eventually.equal(1000);

            const [, limit] = await this.token.isOperator(this.holder, this.operator);
            await expect(decrypt.call(this, limit, this.holder)).to.eventually.equal(300);
          });
        });

        describe('with callback', function () {
          // Transfers `amount` from the holder to `to` as the operator, with the given callback `data`.
          const transferFromAndCall = async function (this: any, to: any, amount: number, data: string) {
            const input = await fhevm
              .createEncryptedInput(await this.token.getAddress(), this.operator.address)
              .add64(amount)
              .encrypt();

            return this.token
              .connect(this.operator)
              ['confidentialTransferFromAndCall(address,address,bytes32,bytes,bytes)'](
                this.holder,
                to,
                input.handles[0],
                input.inputProof,
                data,
              );
          };

          it('a transfer over the limit moves nothing and leaves the limit untouched', async function () {
            await transferFromAndCall.call(this, this.recipient, 301, '0x');

            await expect(
              decrypt.call(this, await this.token.confidentialBalanceOf(this.holder), this.holder),
            ).to.eventually.equal(1000);

            const [, limit] = await this.token.isOperator(this.holder, this.operator);
            await expect(decrypt.call(this, limit, this.holder)).to.eventually.equal(300);
          });

          for (const callbackSuccess of [true, false]) {
            it(`a transfer ${callbackSuccess ? 'accepted' : 'refunded'} by the receiver ${
              callbackSuccess ? 'consumes' : 'does not consume'
            } the limit`, async function () {
              const receiver = await ethers.deployContract('ERC7984ReceiverMock');

              await transferFromAndCall.call(
                this,
                receiver,
                200,
                ethers.AbiCoder.defaultAbiCoder().encode(['bool'], [callbackSuccess]),
              );

              await expect(
                decrypt.call(this, await this.token.confidentialBalanceOf(this.holder), this.holder),
              ).to.eventually.equal(callbackSuccess ? 800 : 1000);

              const [, limit] = await this.token.isOperator(this.holder, this.operator);
              await expect(decrypt.call(this, limit, this.holder)).to.eventually.equal(callbackSuccess ? 100 : 300);
            });
          }
        });
      });

      describe('with a reentrant operator', function () {
        beforeEach(async function () {
          this.reentrant = await ethers.deployContract('ERC7984ReentrantOperatorMock');
        });

        // The operator spends `amount`, then `reentrantAmount` again from within its transfer callback.
        for (const { limit, amount, reentrantAmount, moved, remaining } of [
          { limit: 500, amount: 200, reentrantAmount: 200, moved: 400, remaining: 100 },
          { limit: 300, amount: 200, reentrantAmount: 200, moved: 200, remaining: 100 },
          { limit: 300, amount: 300, reentrantAmount: 300, moved: 300, remaining: 0 },
        ]) {
          it(`spends ${amount} then ${reentrantAmount} with a limit of ${limit}`, async function () {
            await setOperator(this.token, this.holder, this.reentrant.target, until, limit);

            const input = await fhevm
              .createEncryptedInput(await this.token.getAddress(), await this.reentrant.getAddress())
              .add64(amount)
              .add64(reentrantAmount)
              .encrypt();
            await this.reentrant.spend(this.token, this.holder, input.handles[0], input.handles[1], input.inputProof);

            await expect(
              decrypt.call(this, await this.token.confidentialBalanceOf(this.holder), this.holder),
            ).to.eventually.equal(1000 - moved);

            const [, newLimit] = await this.token.isOperator(this.holder, this.reentrant);
            await expect(decrypt.call(this, newLimit, this.holder)).to.eventually.equal(remaining);
          });
        }

        it('the in-flight limit is only transiently accessible to the holder and the operator', async function () {
          await setOperator(this.token, this.holder, this.reentrant.target, until, 500);

          const input = await fhevm
            .createEncryptedInput(await this.token.getAddress(), await this.reentrant.getAddress())
            .add64(200)
            .add64(200)
            .encrypt();
          await this.reentrant.spend(this.token, this.holder, input.handles[0], input.handles[1], input.inputProof);

          // During the callback, both could access the limit left by the outer spend.
          await expect(this.reentrant.operatorCouldAccessInFlightLimit()).to.eventually.be.true;
          await expect(this.reentrant.holderCouldAccessInFlightLimit()).to.eventually.be.true;

          // After the transaction, that limit was replaced and nobody holds a persistent permission on it.
          const acl = await getAcl();
          const inFlightLimit = await this.reentrant.inFlightLimit();
          const [, finalLimit] = await this.token.isOperator(this.holder, this.reentrant);
          expect(finalLimit).to.not.equal(inFlightLimit);
          await expect(acl.isAllowed(inFlightLimit, this.holder)).to.eventually.be.false;
          await expect(acl.isAllowed(inFlightLimit, this.reentrant)).to.eventually.be.false;
          await expect(acl.isAllowed(finalLimit, this.holder)).to.eventually.be.true;
          await expect(acl.isAllowed(finalLimit, this.reentrant)).to.eventually.be.true;
        });
      });

      describe('with a zero limit', function () {
        for (const withProof of [true, false]) {
          it(`${
            withProof ? 'an encrypted zero' : 'an empty handle'
          } registers an operator that can move nothing`, async function () {
            if (withProof) {
              await setOperator(this.token, this.holder, this.operator.address, until, 0);
            } else {
              await this.token.connect(this.holder).setOperator(this.operator.address, until, ethers.ZeroHash, '0x');
            }

            const [isOperator, limit] = await this.token.isOperator(this.holder, this.operator);
            expect(isOperator).to.be.true;
            expect(limit).to.not.equal(UNLIMITED_OPERATOR);

            await transferFrom.call(this, 100);

            await expect(
              decrypt.call(this, await this.token.confidentialBalanceOf(this.holder), this.holder),
            ).to.eventually.equal(1000);

            const [, newLimit] = await this.token.isOperator(this.holder, this.operator);
            await expect(decrypt.call(this, newLimit, this.holder)).to.eventually.equal(0);
          });
        }
      });
    });

    describe('transfer', function () {
      for (const asSender of [true, false]) {
        describe(asSender ? 'as sender' : 'as operator', function () {
          beforeEach(async function () {
            if (!asSender) {
              const timestamp = (await ethers.provider.getBlock('latest'))!.timestamp + 100;
              await setOperator(this.token, this.holder, this.operator.address, timestamp);
            }
          });

          if (!asSender) {
            for (const withCallback of [false, true]) {
              describe(withCallback ? 'with callback' : 'without callback', function () {
                beforeEach(async function () {
                  const encryptedInput = await fhevm
                    .createEncryptedInput(await this.token.getAddress(), this.operator.address)
                    .add64(100)
                    .encrypt();

                  this.params = [
                    this.holder.address,
                    this.recipient.address,
                    encryptedInput.handles[0],
                    encryptedInput.inputProof,
                  ];
                  if (withCallback) {
                    this.params.push('0x');
                  }
                });

                it('without operator approval should fail', async function () {
                  await setOperator(this.token, this.holder, this.operator.address, 0);

                  await expect(
                    this.token
                      .connect(this.operator)
                      [
                        withCallback
                          ? 'confidentialTransferFromAndCall(address,address,bytes32,bytes,bytes)'
                          : 'confidentialTransferFrom(address,address,bytes32,bytes)'
                      ](...this.params),
                  )
                    .to.be.revertedWithCustomError(this.token, 'ERC7984UnauthorizedSpender')
                    .withArgs(this.holder.address, this.operator.address);
                });

                it('should be successful', async function () {
                  await this.token
                    .connect(this.operator)
                    [
                      withCallback
                        ? 'confidentialTransferFromAndCall(address,address,bytes32,bytes,bytes)'
                        : 'confidentialTransferFrom(address,address,bytes32,bytes)'
                    ](...this.params);
                });
              });
            }
          }

          // Edge cases to run with sender as caller
          if (asSender) {
            it('from address with no balance should pass', async function () {
              const encryptedInput = await fhevm
                .createEncryptedInput(await this.token.getAddress(), this.recipient.address)
                .add64(100)
                .encrypt();

              await expect(
                this.token
                  .connect(this.recipient)
                  ['confidentialTransfer(address,bytes32,bytes)'](
                    this.holder.address,
                    encryptedInput.handles[0],
                    encryptedInput.inputProof,
                  ),
              ).to.not.be.reverted;
            });

            it('to zero address', async function () {
              const encryptedInput = await fhevm
                .createEncryptedInput(await this.token.getAddress(), this.holder.address)
                .add64(100)
                .encrypt();

              await expect(
                this.token
                  .connect(this.holder)
                  ['confidentialTransfer(address,bytes32,bytes)'](
                    ethers.ZeroAddress,
                    encryptedInput.handles[0],
                    encryptedInput.inputProof,
                  ),
              )
                .to.be.revertedWithCustomError(this.token, 'ERC7984InvalidReceiver')
                .withArgs(ethers.ZeroAddress);
            });
          }

          for (const sufficientBalance of [false, true]) {
            it(`${sufficientBalance ? 'sufficient' : 'insufficient'} balance`, async function () {
              const transferAmount = sufficientBalance ? 400 : 1100;

              const encryptedInput = await fhevm
                .createEncryptedInput(
                  await this.token.getAddress(),
                  asSender ? this.holder.address : this.operator.address,
                )
                .add64(transferAmount)
                .encrypt();

              let tx;
              if (asSender) {
                tx = await this.token
                  .connect(this.holder)
                  ['confidentialTransfer(address,bytes32,bytes)'](
                    this.recipient.address,
                    encryptedInput.handles[0],
                    encryptedInput.inputProof,
                  );
              } else {
                tx = await this.token
                  .connect(this.operator)
                  ['confidentialTransferFrom(address,address,bytes32,bytes)'](
                    this.holder.address,
                    this.recipient.address,
                    encryptedInput.handles[0],
                    encryptedInput.inputProof,
                  );
              }
              const transferEvent = (await tx.wait()).logs.filter((log: any) => log.address === this.token.target)[0];
              expect(transferEvent.args[0]).to.equal(this.holder.address);
              expect(transferEvent.args[1]).to.equal(this.recipient.address);

              const transferAmountHandle = transferEvent.args[2];
              const holderBalanceHandle = await this.token.confidentialBalanceOf(this.holder);
              const recipientBalanceHandle = await this.token.confidentialBalanceOf(this.recipient);

              await expect(
                fhevm.userDecryptEuint(
                  FhevmType.euint64,
                  transferAmountHandle,
                  await this.token.getAddress(),
                  this.holder,
                ),
              ).to.eventually.equal(sufficientBalance ? transferAmount : 0);
              await expect(
                fhevm.userDecryptEuint(
                  FhevmType.euint64,
                  transferAmountHandle,
                  await this.token.getAddress(),
                  this.recipient,
                ),
              ).to.eventually.equal(sufficientBalance ? transferAmount : 0);
              // Other can not reencrypt the transfer amount
              await expect(
                fhevm.userDecryptEuint(
                  FhevmType.euint64,
                  transferAmountHandle,
                  await this.token.getAddress(),
                  this.operator,
                ),
              ).to.be.rejectedWith(generateDecryptionErrorMessage(transferAmountHandle, this.operator.address));

              await expect(
                fhevm.userDecryptEuint(
                  FhevmType.euint64,
                  holderBalanceHandle,
                  await this.token.getAddress(),
                  this.holder,
                ),
              ).to.eventually.equal(1000 - (sufficientBalance ? transferAmount : 0));
              await expect(
                fhevm.userDecryptEuint(
                  FhevmType.euint64,
                  recipientBalanceHandle,
                  await this.token.getAddress(),
                  this.recipient,
                ),
              ).to.eventually.equal(sufficientBalance ? transferAmount : 0);
            });
          }
        });
      }

      describe('without input proof', function () {
        for (const [usingTransferFrom, withCallback] of [false, true].flatMap(val => [
          [val, false],
          [val, true],
        ])) {
          describe(`using ${usingTransferFrom ? 'confidentialTransferFrom' : 'confidentialTransfer'} ${
            withCallback ? 'with callback' : ''
          }`, function () {
            async function callTransfer(contract: any, from: any, to: any, amount: any, sender: any = from) {
              let functionParams = [to, amount];

              if (withCallback) {
                functionParams.push('0x');
                if (usingTransferFrom) {
                  functionParams.unshift(from);
                  await contract.connect(sender).confidentialTransferFromAndCall(...functionParams);
                } else {
                  await contract
                    .connect(sender)
                    ['confidentialTransferAndCall(address,bytes32,bytes)'](...functionParams);
                }
              } else {
                if (usingTransferFrom) {
                  functionParams.unshift(from);
                  await contract.connect(sender).confidentialTransferFrom(...functionParams);
                } else {
                  await contract.connect(sender)['confidentialTransfer(address,bytes32)'](...functionParams);
                }
              }
            }

            it('full balance', async function () {
              const fullBalanceHandle = await this.token.confidentialBalanceOf(this.holder);

              await callTransfer(this.token, this.holder, this.recipient, fullBalanceHandle);

              await expect(
                fhevm.userDecryptEuint(
                  FhevmType.euint64,
                  await this.token.confidentialBalanceOf(this.recipient),
                  await this.token.getAddress(),
                  this.recipient,
                ),
              ).to.eventually.equal(1000);
            });

            it('other user balance should revert', async function () {
              const encryptedInput = await fhevm
                .createEncryptedInput(await this.token.getAddress(), this.holder.address)
                .add64(100)
                .encrypt();

              await this.token
                .connect(this.holder)
                ['$_mint(address,bytes32,bytes)'](this.recipient, encryptedInput.handles[0], encryptedInput.inputProof);

              const recipientBalanceHandle = await this.token.confidentialBalanceOf(this.recipient);
              await expect(callTransfer(this.token, this.holder, this.recipient, recipientBalanceHandle))
                .to.be.revertedWithCustomError(this.token, 'ERC7984UnauthorizedUseOfEncryptedAmount')
                .withArgs(recipientBalanceHandle, this.holder);
            });

            if (usingTransferFrom) {
              describe('without operator approval', function () {
                beforeEach(async function () {
                  await setOperator(this.token, this.holder, this.operator.address, 0);
                  await allowHandle(this.holder, this.operator, await this.token.confidentialBalanceOf(this.holder));
                });

                it('should revert', async function () {
                  await expect(
                    callTransfer(
                      this.token,
                      this.holder,
                      this.recipient,
                      await this.token.confidentialBalanceOf(this.holder),
                      this.operator,
                    ),
                  )
                    .to.be.revertedWithCustomError(this.token, 'ERC7984UnauthorizedSpender')
                    .withArgs(this.holder.address, this.operator.address);
                });
              });
            }
          });
        }
      });

      it('internal function reverts on from address zero', async function () {
        const encryptedInput = await fhevm
          .createEncryptedInput(await this.token.getAddress(), this.holder.address)
          .add64(100)
          .encrypt();

        await expect(
          this.token
            .connect(this.holder)
            ['$_transfer(address,address,bytes32,bytes)'](
              ethers.ZeroAddress,
              this.recipient.address,
              encryptedInput.handles[0],
              encryptedInput.inputProof,
            ),
        )
          .to.be.revertedWithCustomError(this.token, 'ERC7984InvalidSender')
          .withArgs(ethers.ZeroAddress);
      });
    });

    describe('transfer with callback', function () {
      beforeEach(async function () {
        this.recipientContract = await ethers.deployContract('ERC7984ReceiverMock');

        this.encryptedInput = await fhevm
          .createEncryptedInput(await this.token.getAddress(), this.holder.address)
          .add64(1000)
          .encrypt();
      });

      for (const callbackSuccess of [false, true]) {
        it(`with callback running ${callbackSuccess ? 'successfully' : 'unsuccessfully'}`, async function () {
          const tx = await this.token
            .connect(this.holder)
            ['confidentialTransferAndCall(address,bytes32,bytes,bytes)'](
              this.recipientContract.target,
              this.encryptedInput.handles[0],
              this.encryptedInput.inputProof,
              ethers.AbiCoder.defaultAbiCoder().encode(['bool'], [callbackSuccess]),
            );

          await expect(
            fhevm.userDecryptEuint(
              FhevmType.euint64,
              await this.token.confidentialBalanceOf(this.holder),
              await this.token.getAddress(),
              this.holder,
            ),
          ).to.eventually.equal(callbackSuccess ? 0 : 1000);

          // Verify event contents
          await expect(tx).to.emit(this.recipientContract, 'ConfidentialTransferCallback').withArgs(callbackSuccess);
          const transferEvents = (await tx.wait()).logs.filter((log: any) => log.address === this.token.target);

          const outboundTransferEvent = transferEvents[0];
          const inboundTransferEvent = transferEvents[1];

          expect(outboundTransferEvent.args[0]).to.equal(this.holder.address);
          expect(outboundTransferEvent.args[1]).to.equal(this.recipientContract.target);
          await expect(
            fhevm.userDecryptEuint(
              FhevmType.euint64,
              outboundTransferEvent.args[2],
              await this.token.getAddress(),
              this.holder,
            ),
          ).to.eventually.equal(1000);

          expect(inboundTransferEvent.args[0]).to.equal(this.recipientContract.target);
          expect(inboundTransferEvent.args[1]).to.equal(this.holder.address);
          await expect(
            fhevm.userDecryptEuint(
              FhevmType.euint64,
              inboundTransferEvent.args[2],
              await this.token.getAddress(),
              this.holder,
            ),
          ).to.eventually.equal(callbackSuccess ? 0 : 1000);
        });
      }

      it('with callback returning encrypted value without recipient ACL', async function () {
        const eboolOwner = await ethers.deployContract('ERC7984UnauthorizedReceiverMock', [this.token.target]);
        await eboolOwner.createReturnValue(true);
        const unauthorizedRetval = await eboolOwner.getReturnValue();

        const maliciousReceiver = await ethers.deployContract('ERC7984UnauthorizedReceiverMock', [this.token.target]);
        await maliciousReceiver.setReturnValue(unauthorizedRetval);

        const utils = await ethers.getContractFactory('ERC7984Utils');
        await expect(
          this.token
            .connect(this.holder)
            ['confidentialTransferAndCall(address,bytes32,bytes,bytes)'](
              maliciousReceiver.target,
              this.encryptedInput.handles[0],
              this.encryptedInput.inputProof,
              '0x',
            ),
        )
          .to.be.revertedWithCustomError(utils, 'ERC7984UtilsUnauthorizedUseOfEncryptedAmount')
          .withArgs(unauthorizedRetval, maliciousReceiver.target);
      });

      it('with callback returning an uninitialized value', async function () {
        const receiver = await ethers.deployContract('ERC7984UnauthorizedReceiverMock', [this.token.target]);

        const encryptedInput = await fhevm
          .createEncryptedInput(await this.token.getAddress(), this.holder.address)
          .add64(100)
          .encrypt();

        await this.token
          .connect(this.holder)
          ['confidentialTransferAndCall(address,bytes32,bytes,bytes)'](
            receiver.target,
            encryptedInput.handles[0],
            encryptedInput.inputProof,
            '0x',
          );

        await expect(
          fhevm.userDecryptEuint(
            FhevmType.euint64,
            await this.token.confidentialBalanceOf(this.holder),
            await this.token.getAddress(),
            this.holder,
          ),
        ).to.eventually.equal(1000);
      });

      it('with callback reverting without a reason', async function () {
        await expect(
          this.token
            .connect(this.holder)
            ['confidentialTransferAndCall(address,bytes32,bytes,bytes)'](
              this.recipientContract.target,
              this.encryptedInput.handles[0],
              this.encryptedInput.inputProof,
              '0x',
            ),
        )
          .to.be.revertedWithCustomError(this.token, 'ERC7984InvalidReceiver')
          .withArgs(this.recipientContract.target);
      });

      it('with callback reverting with a custom error', async function () {
        await expect(
          this.token
            .connect(this.holder)
            ['confidentialTransferAndCall(address,bytes32,bytes,bytes)'](
              this.recipientContract.target,
              this.encryptedInput.handles[0],
              this.encryptedInput.inputProof,
              ethers.AbiCoder.defaultAbiCoder().encode(['uint8'], [2]),
            ),
        )
          .to.be.revertedWithCustomError(this.recipientContract, 'InvalidInput')
          .withArgs(2);
      });

      it('to an EOA', async function () {
        await this.token
          .connect(this.holder)
          ['confidentialTransferAndCall(address,bytes32,bytes,bytes)'](
            this.recipient,
            this.encryptedInput.handles[0],
            this.encryptedInput.inputProof,
            '0x',
          );

        const balanceOfHandle = await this.token.confidentialBalanceOf(this.recipient);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, balanceOfHandle, await this.token.getAddress(), this.recipient),
        ).to.eventually.equal(1000);
      });
    });
  });
}

function generateDecryptionErrorMessage(handle: string, account: string): RegExp {
  return new RegExp(`User ${account} is not authorized to decrypt handle ${handle}!`);
}

export { shouldBehaveLikeERC7984 };
