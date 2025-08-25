import { ERC7984ReceiverMock } from '../../../types';
import { $ERC7984Mock } from '../../../types/contracts-exposed/mocks/token/ERC7984Mock.sol/$ERC7984Mock';
import { allowHandle } from '../../helpers/accounts';
import { FhevmType } from '@fhevm/hardhat-plugin';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import { expect } from 'chai';
import hre, { ethers, fhevm } from 'hardhat';

const name = 'ConfidentialFungibleToken';
const symbol = 'CFT';
const uri = 'https://example.com/metadata';

/* eslint-disable no-unexpected-multiline */
function shouldBehaveLikeERC7984(
  deployFixture: () => Promise<{
    token: $ERC7984Mock;
    holder: HardhatEthersSigner;
    recipient: HardhatEthersSigner;
    operator: HardhatEthersSigner;
    anyone: HardhatEthersSigner;
  }>,
) {
  describe('ERC7984', function () {
    describe('constructor', function () {
      it('sets the name', async function () {
        const { token } = await deployFixture();
        await expect(token.name()).to.eventually.equal(name);
      });

      it('sets the symbol', async function () {
        const { token } = await deployFixture();
        await expect(token.symbol()).to.eventually.equal(symbol);
      });

      it('sets the uri', async function () {
        const { token } = await deployFixture();
        await expect(token.tokenURI()).to.eventually.equal(uri);
      });

      it('decimals is 6', async function () {
        const { token } = await deployFixture();
        await expect(token.decimals()).to.eventually.equal(6);
      });
    });

    describe('confidentialBalanceOf', function () {
      it('handle can be reencryped by owner', async function () {
        const { token, holder } = await deployFixture();
        const balanceOfHandleHolder = await token.confidentialBalanceOf(holder);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, balanceOfHandleHolder, await token.getAddress(), holder),
        ).to.eventually.equal(1000);
      });

      it('handle cannot be reencryped by non-owner', async function () {
        const { token, holder, anyone } = await deployFixture();
        const balanceOfHandleHolder = await token.confidentialBalanceOf(holder);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, balanceOfHandleHolder, await token.getAddress(), anyone),
        ).to.be.rejectedWith(generateReencryptionErrorMessage(balanceOfHandleHolder, anyone.address));
      });
    });

    describe('mint', function () {
      for (const existingUser of [false, true]) {
        it(`to ${existingUser ? 'existing' : 'new'} user`, async function () {
          const { token, holder } = await deployFixture();
          if (existingUser) {
            const encryptedInput = await fhevm
              .createEncryptedInput(await token.getAddress(), holder.address)
              .add64(1000)
              .encrypt();

            await token
              .connect(holder)
              ['$_mint(address,bytes32,bytes)'](holder, encryptedInput.handles[0], encryptedInput.inputProof);
          }

          const balanceOfHandleHolder = await token.confidentialBalanceOf(holder);
          await expect(
            fhevm.userDecryptEuint(FhevmType.euint64, balanceOfHandleHolder, await token.getAddress(), holder),
          ).to.eventually.equal(existingUser ? 2000 : 1000);

          // Check total supply
          const totalSupplyHandle = await token.confidentialTotalSupply();
          await token.connect(holder).confidentialTotalSupplyAccess();
          await expect(
            fhevm.userDecryptEuint(FhevmType.euint64, totalSupplyHandle, await token.getAddress(), holder),
          ).to.eventually.equal(existingUser ? 2000 : 1000);
        });
      }

      it('from zero address', async function () {
        const { token, holder } = await deployFixture();
        const encryptedInput = await fhevm
          .createEncryptedInput(await token.getAddress(), holder.address)
          .add64(400)
          .encrypt();

        await expect(
          token
            .connect(holder)
            ['$_mint(address,bytes32,bytes)'](ethers.ZeroAddress, encryptedInput.handles[0], encryptedInput.inputProof),
        )
          .to.be.revertedWithCustomError(token, 'ERC7984InvalidReceiver')
          .withArgs(ethers.ZeroAddress);
      });
    });

    describe('burn', function () {
      for (const sufficientBalance of [false, true]) {
        it(`from a user with ${sufficientBalance ? 'sufficient' : 'insufficient'} balance`, async function () {
          const { token, holder } = await deployFixture();
          const burnAmount = sufficientBalance ? 400 : 1100;

          const encryptedInput = await fhevm
            .createEncryptedInput(await token.getAddress(), holder.address)
            .add64(burnAmount)
            .encrypt();

          await token
            .connect(holder)
            ['$_burn(address,bytes32,bytes)'](holder, encryptedInput.handles[0], encryptedInput.inputProof);

          const balanceOfHandleHolder = await token.confidentialBalanceOf(holder);
          await expect(
            fhevm.userDecryptEuint(FhevmType.euint64, balanceOfHandleHolder, await token.getAddress(), holder),
          ).to.eventually.equal(sufficientBalance ? 600 : 1000);

          // Check total supply
          const totalSupplyHandle = await token.confidentialTotalSupply();
          await token.connect(holder).confidentialTotalSupplyAccess();
          await expect(
            fhevm.userDecryptEuint(FhevmType.euint64, totalSupplyHandle, await token.getAddress(), holder),
          ).to.eventually.equal(sufficientBalance ? 600 : 1000);
        });
      }

      it('from zero address', async function () {
        const { token, holder } = await deployFixture();
        const encryptedInput = await fhevm
          .createEncryptedInput(await token.getAddress(), holder.address)
          .add64(400)
          .encrypt();

        await expect(
          token
            .connect(holder)
            ['$_burn(address,bytes32,bytes)'](ethers.ZeroAddress, encryptedInput.handles[0], encryptedInput.inputProof),
        )
          .to.be.revertedWithCustomError(token, 'ERC7984InvalidSender')
          .withArgs(ethers.ZeroAddress);
      });
    });

    describe('transfer', function () {
      for (const asSender of [true, false]) {
        describe(asSender ? 'as sender' : 'as operator', function () {
          let [holder, recipient, operator]: HardhatEthersSigner[] = [];
          let token: $ERC7984Mock;
          beforeEach(async function () {
            ({ token, holder, recipient, operator } = await deployFixture());
            if (!asSender) {
              const timestamp = (await ethers.provider.getBlock('latest'))!.timestamp + 100;
              await token.connect(holder).setOperator(operator.address, timestamp);
            }
          });

          if (!asSender) {
            for (const withCallback of [false, true]) {
              describe(withCallback ? 'with callback' : 'without callback', function () {
                let encryptedInput: any;
                let params: any;

                beforeEach(async function () {
                  encryptedInput = await fhevm
                    .createEncryptedInput(await token.getAddress(), operator.address)
                    .add64(100)
                    .encrypt();

                  params = [holder.address, recipient.address, encryptedInput.handles[0], encryptedInput.inputProof];
                  if (withCallback) {
                    params.push('0x');
                  }
                });

                it('without operator approval should fail', async function () {
                  await token.$_setOperator(holder, operator, 0);

                  await expect(
                    token
                      .connect(operator)
                      [
                        withCallback
                          ? 'confidentialTransferFromAndCall(address,address,bytes32,bytes,bytes)'
                          : 'confidentialTransferFrom(address,address,bytes32,bytes)'
                      ](...params),
                  )
                    .to.be.revertedWithCustomError(token, 'ERC7984UnauthorizedSpender')
                    .withArgs(holder.address, operator.address);
                });

                it('should be successful', async function () {
                  await token
                    .connect(operator)
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
                .createEncryptedInput(await token.getAddress(), recipient.address)
                .add64(100)
                .encrypt();

              await expect(
                token
                  .connect(recipient)
                  ['confidentialTransfer(address,bytes32,bytes)'](
                    holder.address,
                    encryptedInput.handles[0],
                    encryptedInput.inputProof,
                  ),
              )
                .to.be.revertedWithCustomError(token, 'ERC7984ZeroBalance')
                .withArgs(recipient.address);
            });

            it('to zero address', async function () {
              const encryptedInput = await fhevm
                .createEncryptedInput(await token.getAddress(), holder.address)
                .add64(100)
                .encrypt();

              await expect(
                token
                  .connect(holder)
                  ['confidentialTransfer(address,bytes32,bytes)'](
                    ethers.ZeroAddress,
                    encryptedInput.handles[0],
                    encryptedInput.inputProof,
                  ),
              )
                .to.be.revertedWithCustomError(token, 'ERC7984InvalidReceiver')
                .withArgs(ethers.ZeroAddress);
            });
          }

          for (const sufficientBalance of [false, true]) {
            it(`${sufficientBalance ? 'sufficient' : 'insufficient'} balance`, async function () {
              const transferAmount = sufficientBalance ? 400 : 1100;

              const encryptedInput = await fhevm
                .createEncryptedInput(await token.getAddress(), asSender ? holder.address : operator.address)
                .add64(transferAmount)
                .encrypt();

              let tx;
              if (asSender) {
                tx = await token
                  .connect(holder)
                  ['confidentialTransfer(address,bytes32,bytes)'](
                    recipient.address,
                    encryptedInput.handles[0],
                    encryptedInput.inputProof,
                  );
              } else {
                tx = await token
                  .connect(operator)
                  ['confidentialTransferFrom(address,address,bytes32,bytes)'](
                    holder.address,
                    recipient.address,
                    encryptedInput.handles[0],
                    encryptedInput.inputProof,
                  );
              }
              const transferEvent = (await tx.wait()).logs.filter((log: any) => log.address === token.target)[0];
              expect(transferEvent.args[0]).to.equal(holder.address);
              expect(transferEvent.args[1]).to.equal(recipient.address);

              const transferAmountHandle = transferEvent.args[2];
              const holderBalanceHandle = await token.confidentialBalanceOf(holder);
              const recipientBalanceHandle = await token.confidentialBalanceOf(recipient);

              await expect(
                fhevm.userDecryptEuint(FhevmType.euint64, transferAmountHandle, await token.getAddress(), holder),
              ).to.eventually.equal(sufficientBalance ? transferAmount : 0);
              await expect(
                fhevm.userDecryptEuint(FhevmType.euint64, transferAmountHandle, await token.getAddress(), recipient),
              ).to.eventually.equal(sufficientBalance ? transferAmount : 0);
              // Other can not reencrypt the transfer amount
              await expect(
                fhevm.userDecryptEuint(FhevmType.euint64, transferAmountHandle, await token.getAddress(), operator),
              ).to.be.rejectedWith(generateReencryptionErrorMessage(transferAmountHandle, operator.address));

              await expect(
                fhevm.userDecryptEuint(FhevmType.euint64, holderBalanceHandle, await token.getAddress(), holder),
              ).to.eventually.equal(1000 - (sufficientBalance ? transferAmount : 0));
              await expect(
                fhevm.userDecryptEuint(FhevmType.euint64, recipientBalanceHandle, await token.getAddress(), recipient),
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
              const { token, holder, recipient } = await deployFixture();
              const fullBalanceHandle = await token.confidentialBalanceOf(holder);

              await callTransfer(token, holder, recipient, fullBalanceHandle);

              await expect(
                fhevm.userDecryptEuint(
                  FhevmType.euint64,
                  await token.confidentialBalanceOf(recipient),
                  await token.getAddress(),
                  recipient,
                ),
              ).to.eventually.equal(1000);
            });

            it('other user balance should revert', async function () {
              const { token, holder, recipient } = await deployFixture();
              const encryptedInput = await fhevm
                .createEncryptedInput(await token.getAddress(), holder.address)
                .add64(100)
                .encrypt();

              await token
                .connect(holder)
                ['$_mint(address,bytes32,bytes)'](recipient, encryptedInput.handles[0], encryptedInput.inputProof);

              const recipientBalanceHandle = await token.confidentialBalanceOf(recipient);
              await expect(callTransfer(token, holder, recipient, recipientBalanceHandle))
                .to.be.revertedWithCustomError(token, 'ERC7984UnauthorizedUseOfEncryptedAmount')
                .withArgs(recipientBalanceHandle, holder);
            });

            if (usingTransferFrom) {
              describe('without operator approval', function () {
                let [holder, recipient, operator]: HardhatEthersSigner[] = [];
                let token: $ERC7984Mock;
                beforeEach(async function () {
                  ({ token, holder, recipient, operator } = await deployFixture());
                  await token.connect(holder).setOperator(operator.address, 0);
                  await allowHandle(hre, holder, operator, await token.confidentialBalanceOf(holder));
                });

                it('should revert', async function () {
                  await expect(
                    callTransfer(token, holder, recipient, await token.confidentialBalanceOf(holder), operator),
                  )
                    .to.be.revertedWithCustomError(token, 'ERC7984UnauthorizedSpender')
                    .withArgs(holder.address, operator.address);
                });
              });
            }
          });
        }
      });

      it('internal function reverts on from address zero', async function () {
        const { token, holder, recipient } = await deployFixture();
        const encryptedInput = await fhevm
          .createEncryptedInput(await token.getAddress(), holder.address)
          .add64(100)
          .encrypt();

        await expect(
          token
            .connect(holder)
            ['$_transfer(address,address,bytes32,bytes)'](
              ethers.ZeroAddress,
              recipient.address,
              encryptedInput.handles[0],
              encryptedInput.inputProof,
            ),
        )
          .to.be.revertedWithCustomError(token, 'ERC7984InvalidSender')
          .withArgs(ethers.ZeroAddress);
      });
    });

    describe('transfer with callback', function () {
      let [holder, recipient]: HardhatEthersSigner[] = [];
      let token: $ERC7984Mock;
      let recipientContract: ERC7984ReceiverMock;
      let encryptedInput: any;
      beforeEach(async function () {
        ({ token, holder, recipient } = await deployFixture());
        recipientContract = await ethers.deployContract('ERC7984ReceiverMock');

        encryptedInput = await fhevm
          .createEncryptedInput(await token.getAddress(), holder.address)
          .add64(1000)
          .encrypt();
      });

      for (const callbackSuccess of [false, true]) {
        it(`with callback running ${callbackSuccess ? 'successfully' : 'unsuccessfully'}`, async function () {
          const tx = await token
            .connect(holder)
            ['confidentialTransferAndCall(address,bytes32,bytes,bytes)'](
              recipientContract.target,
              encryptedInput.handles[0],
              encryptedInput.inputProof,
              ethers.AbiCoder.defaultAbiCoder().encode(['bool'], [callbackSuccess]),
            );

          await expect(
            fhevm.userDecryptEuint(
              FhevmType.euint64,
              await token.confidentialBalanceOf(holder),
              await token.getAddress(),
              holder,
            ),
          ).to.eventually.equal(callbackSuccess ? 0 : 1000);

          // Verify event contents
          expect(tx).to.emit(recipientContract, 'ConfidentialTransferCallback').withArgs(callbackSuccess);
          const transferEvents = (await tx.wait()).logs.filter((log: any) => log.address === token.target);

          const outboundTransferEvent = transferEvents[0];
          const inboundTransferEvent = transferEvents[1];

          expect(outboundTransferEvent.args[0]).to.equal(holder.address);
          expect(outboundTransferEvent.args[1]).to.equal(recipientContract.target);
          await expect(
            fhevm.userDecryptEuint(FhevmType.euint64, outboundTransferEvent.args[2], await token.getAddress(), holder),
          ).to.eventually.equal(1000);

          expect(inboundTransferEvent.args[0]).to.equal(recipientContract.target);
          expect(inboundTransferEvent.args[1]).to.equal(holder.address);
          await expect(
            fhevm.userDecryptEuint(FhevmType.euint64, inboundTransferEvent.args[2], await token.getAddress(), holder),
          ).to.eventually.equal(callbackSuccess ? 0 : 1000);
        });
      }

      it('with callback reverting without a reason', async function () {
        await expect(
          token
            .connect(holder)
            ['confidentialTransferAndCall(address,bytes32,bytes,bytes)'](
              recipientContract.target,
              encryptedInput.handles[0],
              encryptedInput.inputProof,
              '0x',
            ),
        )
          .to.be.revertedWithCustomError(token, 'ERC7984InvalidReceiver')
          .withArgs(recipientContract.target);
      });

      it('with callback reverting with a custom error', async function () {
        await expect(
          token
            .connect(holder)
            ['confidentialTransferAndCall(address,bytes32,bytes,bytes)'](
              recipientContract.target,
              encryptedInput.handles[0],
              encryptedInput.inputProof,
              ethers.AbiCoder.defaultAbiCoder().encode(['uint8'], [2]),
            ),
        )
          .to.be.revertedWithCustomError(recipientContract, 'InvalidInput')
          .withArgs(2);
      });

      it('to an EOA', async function () {
        await token
          .connect(holder)
          ['confidentialTransferAndCall(address,bytes32,bytes,bytes)'](
            recipient,
            encryptedInput.handles[0],
            encryptedInput.inputProof,
            '0x',
          );

        const balanceOfHandle = await token.confidentialBalanceOf(recipient);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, balanceOfHandle, await token.getAddress(), recipient),
        ).to.eventually.equal(1000);
      });
    });

    describe('disclose', function () {
      let [holder, recipient]: HardhatEthersSigner[] = [];
      let token: $ERC7984Mock;
      let expectedAmount: any;
      let expectedHandle: any;
      beforeEach(async function () {
        ({ token, holder, recipient } = await deployFixture());
        expectedAmount = undefined;
        expectedHandle = undefined;
      });

      it('user balance', async function () {
        const holderBalanceHandle = await token.confidentialBalanceOf(holder);

        await token.connect(holder).discloseEncryptedAmount(holderBalanceHandle);

        expectedAmount = 1000n;
        expectedHandle = holderBalanceHandle;
      });

      it('transaction amount', async function () {
        const encryptedInput = await fhevm
          .createEncryptedInput(await token.getAddress(), holder.address)
          .add64(400)
          .encrypt();

        const tx = await token['confidentialTransfer(address,bytes32,bytes)'](
          recipient,
          encryptedInput.handles[0],
          encryptedInput.inputProof,
        );

        const transferEvent = (await tx.wait()).logs.filter((log: any) => log.address === token.target)[0];
        const transferAmount = transferEvent.args[2];

        await token.connect(recipient).discloseEncryptedAmount(transferAmount);

        expectedAmount = 400n;
        expectedHandle = transferAmount;
      });

      it("other user's balance", async function () {
        const holderBalanceHandle = await token.confidentialBalanceOf(holder);

        await expect(token.connect(recipient).discloseEncryptedAmount(holderBalanceHandle))
          .to.be.revertedWithCustomError(token, 'ERC7984UnauthorizedUseOfEncryptedAmount')
          .withArgs(holderBalanceHandle, recipient);
      });

      it('invalid signature reverts', async function () {
        const holderBalanceHandle = await token.confidentialBalanceOf(holder);
        await token.connect(holder).discloseEncryptedAmount(holderBalanceHandle);

        await expect(token.connect(holder).finalizeDiscloseEncryptedAmount(0, 0, [])).to.be.reverted;
      });

      afterEach(async function () {
        if (expectedHandle === undefined || expectedAmount === undefined) return;

        await fhevm.awaitDecryptionOracle();

        // Check that event was correctly emitted
        const eventFilter = token.filters.AmountDisclosed();
        const discloseEvent = (await token.queryFilter(eventFilter))[0];
        expect(discloseEvent.args[0]).to.equal(expectedHandle);
        expect(discloseEvent.args[1]).to.equal(expectedAmount);
      });
    });
  });
}
/* eslint-enable no-unexpected-multiline */

function generateReencryptionErrorMessage(handle: string, account: string): string {
  return `User ${account} is not authorized to user decrypt handle ${handle}`;
}

export { shouldBehaveLikeERC7984 };
