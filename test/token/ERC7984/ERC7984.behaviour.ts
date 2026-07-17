import { $ERC7984Mock } from '../../../types/contracts-exposed/mocks/token/ERC7984/ERC7984Mock.sol/$ERC7984Mock';
import { allowHandle } from '../../helpers/accounts';
import { FhevmType } from '@fhevm/hardhat-plugin';
import { expect } from 'chai';
import hre, { ethers, fhevm } from 'hardhat';

const name = 'ConfidentialFungibleToken';
const symbol = 'CFT';
const uri = 'https://example.com/metadata';

// Deploys an ERC7984 mock (or a compatible extension mock) and mints 1000 tokens to `holder`.
// Returns the props consumed by `shouldBehaveLikeERC7984`, meant to be assigned onto the Mocha
// context via `Object.assign(this, await deployERC7984Fixture())` in a `beforeEach` hook.
async function deployERC7984Fixture(contract: string = '$ERC7984Mock', extraDeploymentArgs: any[] = []) {
  const [holder, recipient, operator, anyone] = await ethers.getSigners();
  const token = (await ethers.deployContract(contract, [
    name,
    symbol,
    uri,
    ...extraDeploymentArgs,
  ])) as any as $ERC7984Mock;
  const encryptedInput = await fhevm
    .createEncryptedInput(await token.getAddress(), holder.address)
    .add64(1000)
    .encrypt();
  await token
    .connect(holder)
    ['$_mint(address,bytes32,bytes)'](holder, encryptedInput.handles[0], encryptedInput.inputProof);
  return { token, holder, recipient, operator, anyone };
}

// Shared behaviour for ERC7984 tokens. Callers pass the mock contract name (and any extra
// constructor args); the suite deploys it and assigns `token`, `holder`, `recipient`, `operator`
// and `anyone` onto the Mocha context before each test.
function shouldBehaveLikeERC7984(contract?: string, ...extraDeploymentArgs: any[]) {
  describe('behaves like ERC7984', function () {
    beforeEach(async function () {
      Object.assign(this, await deployERC7984Fixture(contract, extraDeploymentArgs));
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

      it('decimals is 6', async function () {
        await expect(this.token.decimals()).to.eventually.equal(6);
      });
    });

    describe('confidentialBalanceOf', function () {
      it('handle can be reencryped by owner', async function () {
        const balanceOfHandleHolder = await this.token.confidentialBalanceOf(this.holder);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, balanceOfHandleHolder, await this.token.getAddress(), this.holder),
        ).to.eventually.equal(1000);
      });

      it('handle cannot be reencryped by non-owner', async function () {
        const balanceOfHandleHolder = await this.token.confidentialBalanceOf(this.holder);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, balanceOfHandleHolder, await this.token.getAddress(), this.anyone),
        ).to.be.rejectedWith(generateReencryptionErrorMessage(balanceOfHandleHolder, this.anyone.address));
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
                  await this.token.$_setOperator(this.holder, this.operator, 0);

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
              ).to.be.rejectedWith(generateReencryptionErrorMessage(transferAmountHandle, this.operator.address));

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
                  await contract.connect(sender).confidentialTransferAndCall(...functionParams);
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
                  await this.token.connect(this.holder).setOperator(this.operator.address, 0);
                  await allowHandle(
                    hre,
                    this.holder,
                    this.operator,
                    await this.token.confidentialBalanceOf(this.holder),
                  );
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
          expect(tx).to.emit(this.recipientContract, 'ConfidentialTransferCallback').withArgs(callbackSuccess);
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

function generateReencryptionErrorMessage(handle: string, account: string): string {
  return `User ${account} is not authorized to user decrypt handle ${handle}`;
}

export { deployERC7984Fixture, shouldBehaveLikeERC7984 };
