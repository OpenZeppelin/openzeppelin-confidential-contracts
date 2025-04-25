import { expect } from "chai";
import { ethers } from "hardhat";

import { createInstance } from "../_template/instance";
import { reencryptEuint64 } from "../_template/reencrypt";

const name = "ConfidentialFungibleToken";
const symbol = "CFT";
const uri = "https://example.com/metadata";

/* eslint-disable no-unexpected-multiline */
describe("ConfidentialFungibleToken", function () {
  beforeEach(async function () {
    const accounts = await ethers.getSigners();
    const [holder, recipient, operator] = accounts;

    const token = await ethers.deployContract("ConfidentialFungibleTokenMock", [name, symbol, uri]);
    this.accounts = accounts.slice(3);
    this.holder = holder;
    this.recipient = recipient;
    this.token = token;
    this.operator = operator;
    this.fhevm = await createInstance();

    const input = this.fhevm.createEncryptedInput(this.token.target, this.holder.address);
    input.add64(1000);
    const encryptedInput = await input.encrypt();

    await this.token
      .connect(this.holder)
      ["$_mint(address,bytes32,bytes)"](this.holder, encryptedInput.handles[0], encryptedInput.inputProof);
  });

  describe("mint", function () {
    for (const existingUser of [false, true]) {
      it(`to ${existingUser ? "existing" : "new"} user`, async function () {
        if (existingUser) {
          const input = this.fhevm.createEncryptedInput(this.token.target, this.holder.address);
          input.add64(1000);
          const encryptedInput = await input.encrypt();

          await this.token
            .connect(this.holder)
            ["$_mint(address,bytes32,bytes)"](this.holder, encryptedInput.handles[0], encryptedInput.inputProof);
        }

        const balanceOfHandleHolder = await this.token.balanceOf(this.holder);
        await expect(
          reencryptEuint64(this.holder, this.fhevm, balanceOfHandleHolder, this.token.target),
        ).to.eventually.equal(existingUser ? 2000 : 1000);

        // Check total supply
        const totalSupplyHandle = await this.token.totalSupply();
        await expect(
          reencryptEuint64(this.holder, this.fhevm, totalSupplyHandle, this.token.target),
        ).to.eventually.equal(existingUser ? 2000 : 1000);
      });
    }

    it("from zero address", async function () {
      const input = this.fhevm.createEncryptedInput(this.token.target, this.holder.address);
      input.add64(400);
      const encryptedInput = await input.encrypt();

      await expect(
        this.token
          .connect(this.holder)
          ["$_mint(address,bytes32,bytes)"](ethers.ZeroAddress, encryptedInput.handles[0], encryptedInput.inputProof),
      )
        .to.be.revertedWithCustomError(this.token, "ConfidentialFungibleTokenInvalidReceiver")
        .withArgs(ethers.ZeroAddress);
    });
  });

  describe("burn", function () {
    for (const sufficientBalance of [false, true]) {
      it(`from a user with ${sufficientBalance ? "sufficient" : "insufficient"} balance`, async function () {
        const burnAmount = sufficientBalance ? 400 : 1100;

        const input = this.fhevm.createEncryptedInput(this.token.target, this.holder.address);
        input.add64(burnAmount);
        const encryptedInput = await input.encrypt();

        await this.token
          .connect(this.holder)
          ["$_burn(address,bytes32,bytes)"](this.holder, encryptedInput.handles[0], encryptedInput.inputProof);

        const balanceOfHandleHolder = await this.token.balanceOf(this.holder);
        await expect(
          reencryptEuint64(this.holder, this.fhevm, balanceOfHandleHolder, this.token.target),
        ).to.eventually.equal(sufficientBalance ? 600 : 1000);

        // Check total supply
        const totalSupplyHandle = await this.token.totalSupply();
        await expect(
          reencryptEuint64(this.holder, this.fhevm, totalSupplyHandle, this.token.target),
        ).to.eventually.equal(sufficientBalance ? 600 : 1000);
      });
    }

    it("from zero address", async function () {
      const input = this.fhevm.createEncryptedInput(this.token.target, this.holder.address);
      input.add64(400);
      const encryptedInput = await input.encrypt();

      await expect(
        this.token
          .connect(this.holder)
          ["$_burn(address,bytes32,bytes)"](ethers.ZeroAddress, encryptedInput.handles[0], encryptedInput.inputProof),
      )
        .to.be.revertedWithCustomError(this.token, "ConfidentialFungibleTokenInvalidSender")
        .withArgs(ethers.ZeroAddress);
    });
  });

  describe("transfer", function () {
    for (const asSender of [true, false]) {
      describe(asSender ? "as sender" : "as operator", function () {
        beforeEach(async function () {
          if (!asSender) {
            const timestamp = (await ethers.provider.getBlock("latest"))!.timestamp + 100;
            await this.token.connect(this.holder).setOperator(this.operator.address, timestamp);
          }
        });

        if (!asSender) {
          it("without operator approval should fail", async function () {
            await this.token.$_setOperator(this.holder, this.operator, 0);

            const input = this.fhevm.createEncryptedInput(this.token.target, this.operator.address);
            input.add64(100);
            const encryptedInput = await input.encrypt();

            await expect(
              this.token
                .connect(this.operator)
                ["confidentialTransferFrom(address,address,bytes32,bytes)"](
                  this.holder.address,
                  this.recipient.address,
                  encryptedInput.handles[0],
                  encryptedInput.inputProof,
                ),
            )
              .to.be.revertedWithCustomError(this.token, "ConfidentialFungibleTokenUnauthorizedSpender")
              .withArgs(this.holder.address, this.operator.address);
          });
        }

        // Edge cases to run with sender as caller
        if (asSender) {
          it("with no balance should revert", async function () {
            const input = this.fhevm.createEncryptedInput(this.token.target, this.recipient.address);
            input.add64(100);
            const encryptedInput = await input.encrypt();

            await expect(
              this.token
                .connect(this.recipient)
                ["confidentialTransfer(address,bytes32,bytes)"](
                  this.holder.address,
                  encryptedInput.handles[0],
                  encryptedInput.inputProof,
                ),
            )
              .to.be.revertedWithCustomError(this.token, "ConfidentialFungibleTokenZeroBalance")
              .withArgs(this.recipient.address);
          });

          it("to zero address", async function () {
            const input = this.fhevm.createEncryptedInput(this.token.target, this.holder.address);
            input.add64(100);
            const encryptedInput = await input.encrypt();

            await expect(
              this.token
                .connect(this.holder)
                ["confidentialTransfer(address,bytes32,bytes)"](
                  ethers.ZeroAddress,
                  encryptedInput.handles[0],
                  encryptedInput.inputProof,
                ),
            )
              .to.be.revertedWithCustomError(this.token, "ConfidentialFungibleTokenInvalidReceiver")
              .withArgs(ethers.ZeroAddress);
          });
        }

        for (const sufficientBalance of [false, true]) {
          it(`${sufficientBalance ? "sufficient" : "insufficient"} balance`, async function () {
            const transferAmount = sufficientBalance ? 400 : 1100;
            const input = this.fhevm.createEncryptedInput(
              this.token.target,
              asSender ? this.holder.address : this.operator.address,
            );
            input.add64(transferAmount);
            const encryptedInput = await input.encrypt();

            let tx;
            if (asSender) {
              tx = await this.token
                .connect(this.holder)
                ["confidentialTransfer(address,bytes32,bytes)"](
                  this.recipient.address,
                  encryptedInput.handles[0],
                  encryptedInput.inputProof,
                );
            } else {
              tx = await this.token
                .connect(this.operator)
                ["confidentialTransferFrom(address,address,bytes32,bytes)"](
                  this.holder.address,
                  this.recipient.address,
                  encryptedInput.handles[0],
                  encryptedInput.inputProof,
                );
            }
            const transferEvent = (await tx.wait()).logs.filter((log) => log.address === this.token.target)[0];
            expect(transferEvent.args[0]).to.equal(this.holder.address);
            expect(transferEvent.args[1]).to.equal(this.recipient.address);

            const transferAmountHandle = transferEvent.args[2];
            const holderBalanceHandle = await this.token.balanceOf(this.holder);
            const recipientBalanceHandle = await this.token.balanceOf(this.recipient);

            await expect(
              reencryptEuint64(this.holder, this.fhevm, transferAmountHandle, this.token.target),
            ).to.eventually.equal(sufficientBalance ? transferAmount : 0);
            await expect(
              reencryptEuint64(this.recipient, this.fhevm, transferAmountHandle, this.token.target),
            ).to.eventually.equal(sufficientBalance ? transferAmount : 0);

            await expect(
              reencryptEuint64(this.holder, this.fhevm, holderBalanceHandle, this.token.target),
            ).to.eventually.equal(1000 - (sufficientBalance ? transferAmount : 0));
            await expect(
              reencryptEuint64(this.recipient, this.fhevm, recipientBalanceHandle, this.token.target),
            ).to.eventually.equal(sufficientBalance ? transferAmount : 0);
          });
        }
      });
    }
  });

  describe("transfer with callback", function () {
    beforeEach(async function () {
      this.recipientContract = await ethers.deployContract("ConfidentialFungibleTokenReceiverMock");

      const input = this.fhevm.createEncryptedInput(this.token.target, this.holder.address);
      input.add64(1000);
      this.encryptedInput = await input.encrypt();
    });

    for (const callbackSuccess of [false, true]) {
      it(`with callback running ${callbackSuccess ? "successfully" : "unsuccessfully"}`, async function () {
        const tx = await this.token
          .connect(this.holder)
          ["confidentialTransferAndCall(address,bytes32,bytes,bytes)"](
            this.recipientContract.target,
            this.encryptedInput.handles[0],
            this.encryptedInput.inputProof,
            ethers.AbiCoder.defaultAbiCoder().encode(["bool"], [callbackSuccess]),
          );

        await expect(
          reencryptEuint64(this.holder, this.fhevm, await this.token.balanceOf(this.holder), this.token.target),
        ).to.eventually.equal(callbackSuccess ? 0 : 1000);

        // Verify event contents
        expect(tx).to.emit(this.recipientContract, "ConfidentialTransferCallback").withArgs(callbackSuccess);
        const transferEvents = (await tx.wait()).logs.filter((log) => log.address === this.token.target);

        const outboundTransferEvent = transferEvents[0];
        const inboundTransferEvent = transferEvents[1];

        expect(outboundTransferEvent.args[0]).to.equal(this.holder.address);
        expect(outboundTransferEvent.args[1]).to.equal(this.recipientContract.target);
        await expect(
          reencryptEuint64(this.holder, this.fhevm, outboundTransferEvent.args[2], this.token.target),
        ).to.eventually.equal(1000);

        expect(inboundTransferEvent.args[0]).to.equal(this.recipientContract.target);
        expect(inboundTransferEvent.args[1]).to.equal(this.holder.address);
        await expect(
          reencryptEuint64(this.holder, this.fhevm, inboundTransferEvent.args[2], this.token.target),
        ).to.eventually.equal(callbackSuccess ? 0 : 1000);
      });
    }

    it("with callback reverting without a reason", async function () {
      await expect(
        this.token
          .connect(this.holder)
          ["confidentialTransferAndCall(address,bytes32,bytes,bytes)"](
            this.recipientContract.target,
            this.encryptedInput.handles[0],
            this.encryptedInput.inputProof,
            "0x",
          ),
      )
        .to.be.revertedWithCustomError(this.token, "ConfidentialFungibleTokenInvalidReceiver")
        .withArgs(this.recipientContract.target);
    });

    it("with callback reverting with a custom error", async function () {
      await expect(
        this.token
          .connect(this.holder)
          ["confidentialTransferAndCall(address,bytes32,bytes,bytes)"](
            this.recipientContract.target,
            this.encryptedInput.handles[0],
            this.encryptedInput.inputProof,
            ethers.AbiCoder.defaultAbiCoder().encode(["uint8"], [2]),
          ),
      )
        .to.be.revertedWithCustomError(this.recipientContract, "InvalidInput")
        .withArgs(2);
    });

    it("to an EOA", async function () {
      await this.token
        .connect(this.holder)
        ["confidentialTransferAndCall(address,bytes32,bytes,bytes)"](
          this.recipient,
          this.encryptedInput.handles[0],
          this.encryptedInput.inputProof,
          "0x",
        );

      const balanceOfHandle = await this.token.balanceOf(this.recipient);
      await expect(
        reencryptEuint64(this.recipient, this.fhevm, balanceOfHandle, this.token.target),
      ).to.eventually.equal(1000);
    });
  });
});
/* eslint-enable no-unexpected-multiline */
