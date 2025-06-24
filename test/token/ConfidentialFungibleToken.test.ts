import { allowHandle } from '../helpers/accounts';
import { FhevmType } from '@fhevm/hardhat-plugin';
import { expect } from 'chai';
import hre, { ethers, fhevm } from 'hardhat';

const name = 'ConfidentialFungibleToken';
const symbol = 'CFT';
const uri = 'https://example.com/metadata';

/* eslint-disable no-unexpected-multiline */
describe('ConfidentialFungibleToken', function () {
  beforeEach(async function () {
    const accounts = await ethers.getSigners();
    const [holder, recipient, operator] = accounts;

    const token = await ethers.deployContract('$ConfidentialFungibleTokenMock', [name, symbol, uri]);
    this.accounts = accounts.slice(3);
    this.holder = holder;
    this.recipient = recipient;
    this.token = token;
    this.operator = operator;

    const encryptedInput = await fhevm
      .createEncryptedInput(this.token.target, this.holder.address)
      .add64(1000)
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
      await expect(this.token.tokenURI()).to.eventually.equal(uri);
    });

    it('decimals are 9', async function () {
      await expect(this.token.decimals()).to.eventually.equal(9);
    });
  });

  describe('balanceOf', function () {
    it('handle can be reencryped by owner', async function () {
      const balanceOfHandleHolder = await this.token.balanceOf(this.holder);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, balanceOfHandleHolder, this.token.target, this.holder),
      ).to.eventually.equal(1000);
    });

    it('handle cannot be reencryped by non-owner', async function () {
      const balanceOfHandleHolder = await this.token.balanceOf(this.holder);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, balanceOfHandleHolder, this.token.target, this.accounts[0]),
      ).to.be.rejectedWith(generateReencryptionErrorMessage(balanceOfHandleHolder, this.accounts[0].address));
    });
  });

  describe('mint', function () {
    for (const existingUser of [false, true]) {
      it(`to ${existingUser ? 'existing' : 'new'} user`, async function () {
        if (existingUser) {
          const encryptedInput = await fhevm
            .createEncryptedInput(this.token.target, this.holder.address)
            .add64(1000)
            .encrypt();

          await this.token
            .connect(this.holder)
            ['$_mint(address,bytes32,bytes)'](this.holder, encryptedInput.handles[0], encryptedInput.inputProof);
        }

        const balanceOfHandleHolder = await this.token.balanceOf(this.holder);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, balanceOfHandleHolder, this.token.target, this.holder),
        ).to.eventually.equal(existingUser ? 2000 : 1000);

        // Check total supply
        const totalSupplyHandle = await this.token.totalSupply();
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, totalSupplyHandle, this.token.target, this.holder),
        ).to.eventually.equal(existingUser ? 2000 : 1000);
      });
    }

    it('from zero address', async function () {
      const encryptedInput = await fhevm
        .createEncryptedInput(this.token.target, this.holder.address)
        .add64(400)
        .encrypt();

      await expect(
        this.token
          .connect(this.holder)
          ['$_mint(address,bytes32,bytes)'](ethers.ZeroAddress, encryptedInput.handles[0], encryptedInput.inputProof),
      )
        .to.be.revertedWithCustomError(this.token, 'ConfidentialFungibleTokenInvalidReceiver')
        .withArgs(ethers.ZeroAddress);
    });
  });

  describe('burn', function () {
    for (const sufficientBalance of [false, true]) {
      it(`from a user with ${sufficientBalance ? 'sufficient' : 'insufficient'} balance`, async function () {
        const burnAmount = sufficientBalance ? 400 : 1100;

        const encryptedInput = await fhevm
          .createEncryptedInput(this.token.target, this.holder.address)
          .add64(burnAmount)
          .encrypt();

        await this.token
          .connect(this.holder)
          ['$_burn(address,bytes32,bytes)'](this.holder, encryptedInput.handles[0], encryptedInput.inputProof);

        const balanceOfHandleHolder = await this.token.balanceOf(this.holder);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, balanceOfHandleHolder, this.token.target, this.holder),
        ).to.eventually.equal(sufficientBalance ? 600 : 1000);

        // Check total supply
        const totalSupplyHandle = await this.token.totalSupply();
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, totalSupplyHandle, this.token.target, this.holder),
        ).to.eventually.equal(sufficientBalance ? 600 : 1000);
      });
    }

    it('from zero address', async function () {
      const encryptedInput = await fhevm
        .createEncryptedInput(this.token.target, this.holder.address)
        .add64(400)
        .encrypt();

      await expect(
        this.token
          .connect(this.holder)
          ['$_burn(address,bytes32,bytes)'](ethers.ZeroAddress, encryptedInput.handles[0], encryptedInput.inputProof),
      )
        .to.be.revertedWithCustomError(this.token, 'ConfidentialFungibleTokenInvalidSender')
        .withArgs(ethers.ZeroAddress);
    });
  });

  describe('transfer', function () {
    for (const asSender of [true, false]) {
      describe(asSender ? 'as sender' : 'as operator', function () {
        beforeEach(async function () {
          if (!asSender) {
            const timestamp = (await ethers.provider.getBlock('latest'))!.timestamp + 100;
            await this.token.connect(this.holder).setOperator(this.operator.address, timestamp);
          }
        });

        if (!asSender) {
          for (const withCallback of [false, true]) {
            describe(withCallback ? 'with callback' : 'without callback', function () {
              let encryptedInput: any;
              let params: any;

              beforeEach(async function () {
                encryptedInput = await fhevm
                  .createEncryptedInput(this.token.target, this.operator.address)
                  .add64(100)
                  .encrypt();

                params = [
                  this.holder.address,
                  this.recipient.address,
                  encryptedInput.handles[0],
                  encryptedInput.inputProof,
                ];
                if (withCallback) {
                  params.push('0x');
                }
              });

              it('without operator approval should fail', async function () {
                await this.token.$_setOperator(this.holder, this.operator, 0);

                await expect(
                  this.token
                    .connect(this.operator)
                    [
                      withCallback
                        ? 'confidentialTransferFromAndCall(address,address,bytes32,bytes,bytes)'
                        : 'confidentialTransferFrom(address,address,bytes32,bytes)'
                    ](...params),
                )
                  .to.be.revertedWithCustomError(this.token, 'ConfidentialFungibleTokenUnauthorizedSpender')
                  .withArgs(this.holder.address, this.operator.address);
              });

              it('should be successful', async function () {
                await this.token
                  .connect(this.operator)
                  [
                    withCallback
                      ? 'confidentialTransferFromAndCall(address,address,bytes32,bytes,bytes)'
                      : 'confidentialTransferFrom(address,address,bytes32,bytes)'
                  ](...params);
              });
            });
          }
        }

        // Edge cases to run with sender as caller
        if (asSender) {
          it('with no balance should revert', async function () {
            const encryptedInput = await fhevm
              .createEncryptedInput(this.token.target, this.recipient.address)
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
            )
              .to.be.revertedWithCustomError(this.token, 'ConfidentialFungibleTokenZeroBalance')
              .withArgs(this.recipient.address);
          });

          it('to zero address', async function () {
            const encryptedInput = await fhevm
              .createEncryptedInput(this.token.target, this.holder.address)
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
              .to.be.revertedWithCustomError(this.token, 'ConfidentialFungibleTokenInvalidReceiver')
              .withArgs(ethers.ZeroAddress);
          });
        }

        for (const sufficientBalance of [false, true]) {
          it(`${sufficientBalance ? 'sufficient' : 'insufficient'} balance`, async function () {
            const transferAmount = sufficientBalance ? 400 : 1100;

            const encryptedInput = await fhevm
              .createEncryptedInput(this.token.target, asSender ? this.holder.address : this.operator.address)
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
            const holderBalanceHandle = await this.token.balanceOf(this.holder);
            const recipientBalanceHandle = await this.token.balanceOf(this.recipient);

            await expect(
              fhevm.userDecryptEuint(FhevmType.euint64, transferAmountHandle, this.token.target, this.holder),
            ).to.eventually.equal(sufficientBalance ? transferAmount : 0);
            await expect(
              fhevm.userDecryptEuint(FhevmType.euint64, transferAmountHandle, this.token.target, this.recipient),
            ).to.eventually.equal(sufficientBalance ? transferAmount : 0);
            // Other can not reencrypt the transfer amount
            await expect(
              fhevm.userDecryptEuint(FhevmType.euint64, transferAmountHandle, this.token.target, this.operator),
            ).to.be.rejectedWith(generateReencryptionErrorMessage(transferAmountHandle, this.operator.address));

            await expect(
              fhevm.userDecryptEuint(FhevmType.euint64, holderBalanceHandle, this.token.target, this.holder),
            ).to.eventually.equal(1000 - (sufficientBalance ? transferAmount : 0));
            await expect(
              fhevm.userDecryptEuint(FhevmType.euint64, recipientBalanceHandle, this.token.target, this.recipient),
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
                await contract.connect(sender).confidentialTransferAndCall(...functionParams);
              }
            } else {
              if (usingTransferFrom) {
                functionParams.unshift(from);
                await contract.connect(sender).confidentialTransferFrom(...functionParams);
              } else {
                await contract.connect(sender).confidentialTransfer(...functionParams);
              }
            }
          }

          it('full balance', async function () {
            const fullBalanceHandle = await this.token.balanceOf(this.holder);

            await callTransfer(this.token, this.holder, this.recipient, fullBalanceHandle);

            await expect(
              fhevm.userDecryptEuint(
                FhevmType.euint64,
                await this.token.balanceOf(this.recipient),
                this.token.target,
                this.recipient,
              ),
            ).to.eventually.equal(1000);
          });

          it('other user balance should revert', async function () {
            const encryptedInput = await fhevm
              .createEncryptedInput(this.token.target, this.holder.address)
              .add64(100)
              .encrypt();

            await this.token
              .connect(this.holder)
              ['$_mint(address,bytes32,bytes)'](this.recipient, encryptedInput.handles[0], encryptedInput.inputProof);

            const recipientBalanceHandle = await this.token.balanceOf(this.recipient);
            await expect(callTransfer(this.token, this.holder, this.recipient, recipientBalanceHandle))
              .to.be.revertedWithCustomError(this.token, 'ConfidentialFungibleTokenUnauthorizedUseOfEncryptedAmount')
              .withArgs(recipientBalanceHandle, this.holder);
          });

          if (usingTransferFrom) {
            describe('without operator approval', function () {
              beforeEach(async function () {
                await this.token.connect(this.holder).setOperator(this.operator.address, 0);
                await allowHandle(hre, this.holder, this.operator, await this.token.balanceOf(this.holder));
              });

              it('should revert', async function () {
                await expect(
                  callTransfer(
                    this.token,
                    this.holder,
                    this.recipient,
                    await this.token.balanceOf(this.holder),
                    this.operator,
                  ),
                )
                  .to.be.revertedWithCustomError(this.token, 'ConfidentialFungibleTokenUnauthorizedSpender')
                  .withArgs(this.holder.address, this.operator.address);
              });
            });
          }
        });
      }
    });

    it('internal function reverts on from address zero', async function () {
      const encryptedInput = await fhevm
        .createEncryptedInput(this.token.target, this.holder.address)
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
        .to.be.revertedWithCustomError(this.token, 'ConfidentialFungibleTokenInvalidSender')
        .withArgs(ethers.ZeroAddress);
    });
  });

  describe('transfer with callback', function () {
    beforeEach(async function () {
      this.recipientContract = await ethers.deployContract('ConfidentialFungibleTokenReceiverMock');

      this.encryptedInput = await fhevm
        .createEncryptedInput(this.token.target, this.holder.address)
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
            await this.token.balanceOf(this.holder),
            this.token.target,
            this.holder,
          ),
        ).to.eventually.equal(callbackSuccess ? 0 : 1000);

        // Verify event contents
        expect(tx).to.emit(this.recipientContract, 'ConfidentialTransferCallback').withArgs(callbackSuccess);
        const transferEvents = (await tx.wait()).logs.filter((log: any) => log.address === this.token.target);

        const outboundTransferEvent = transferEvents[0];
        const inboundTransferEvent = transferEvents[1];

        expect(outboundTransferEvent.args[0]).to.equal(this.holder.address);
        expect(outboundTransferEvent.args[1]).to.equal(this.recipientContract.target);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, outboundTransferEvent.args[2], this.token.target, this.holder),
        ).to.eventually.equal(1000);

        expect(inboundTransferEvent.args[0]).to.equal(this.recipientContract.target);
        expect(inboundTransferEvent.args[1]).to.equal(this.holder.address);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, inboundTransferEvent.args[2], this.token.target, this.holder),
        ).to.eventually.equal(callbackSuccess ? 0 : 1000);
      });
    }

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
        .to.be.revertedWithCustomError(this.token, 'ConfidentialFungibleTokenInvalidReceiver')
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

      const balanceOfHandle = await this.token.balanceOf(this.recipient);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, balanceOfHandle, this.token.target, this.recipient),
      ).to.eventually.equal(1000);
    });
  });

  describe('disclose', function () {
    let expectedAmount: any;
    let expectedHandle: any;

    beforeEach(async function () {
      expectedAmount = undefined;
      expectedHandle = undefined;
    });

    it('user balance', async function () {
      const holderBalanceHandle = await this.token.balanceOf(this.holder);

      await this.token.connect(this.holder).discloseEncryptedAmount(holderBalanceHandle);

      expectedAmount = 1000n;
      expectedHandle = holderBalanceHandle;
    });

    it('transaction amount', async function () {
      const encryptedInput = await fhevm
        .createEncryptedInput(this.token.target, this.holder.address)
        .add64(400)
        .encrypt();

      const tx = await this.token['confidentialTransfer(address,bytes32,bytes)'](
        this.recipient,
        encryptedInput.handles[0],
        encryptedInput.inputProof,
      );

      const transferEvent = (await tx.wait()).logs.filter((log: any) => log.address === this.token.target)[0];
      const transferAmount = transferEvent.args[2];

      await this.token.connect(this.recipient).discloseEncryptedAmount(transferAmount);

      expectedAmount = 400n;
      expectedHandle = transferAmount;
    });

    it("other user's balance", async function () {
      const holderBalanceHandle = await this.token.balanceOf(this.holder);

      await expect(this.token.connect(this.recipient).discloseEncryptedAmount(holderBalanceHandle))
        .to.be.revertedWithCustomError(this.token, 'ConfidentialFungibleTokenUnauthorizedUseOfEncryptedAmount')
        .withArgs(holderBalanceHandle, this.recipient);
    });

    it('invalid signature reverts', async function () {
      const holderBalanceHandle = await this.token.balanceOf(this.holder);
      await this.token.connect(this.holder).discloseEncryptedAmount(holderBalanceHandle);

      await expect(this.token.connect(this.holder).finalizeDiscloseEncryptedAmount(0, 0, [])).to.be.reverted;
    });

    afterEach(async function () {
      if (expectedHandle === undefined || expectedAmount === undefined) return;

      await fhevm.awaitDecryptionOracle();

      // Check that event was correctly emitted
      const eventFilter = this.token.filters.EncryptedAmountDisclosed();
      const discloseEvent = (await this.token.queryFilter(eventFilter))[0];
      expect(discloseEvent.args[0]).to.equal(expectedHandle);
      expect(discloseEvent.args[1]).to.equal(expectedAmount);
    });
  });
});
/* eslint-enable no-unexpected-multiline */

function generateReencryptionErrorMessage(handle: string, account: string): string {
  return `User ${account} is not authorized to user decrypt handle ${handle}`;
}
