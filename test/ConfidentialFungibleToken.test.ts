import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";

import { createInstance } from "./_template/instance";
import { reencryptEuint64 } from "./_template/reencrypt";

const name = "ConfidentialFungibleToken";
const symbol = "CFT";
const uri = "https://example.com/metadata";

/* eslint-disable no-unexpected-multiline */
describe.only("ConfidentialFungibleToken", function () {
  const fixture = async () => {
    const accounts = await ethers.getSigners();
    const [holder, recipient, operator] = accounts;

    const token = await ethers.deployContract("ConfidentialFungibleTokenMock", [name, symbol, uri]);

    return { accounts: accounts.slice(3), holder, recipient, token, operator };
  };

  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
    this.fhevm = await createInstance();
  });

  describe("mint", function () {
    beforeEach(async function () {
      const input = this.fhevm.createEncryptedInput(this.token.target, this.holder.address);
      input.add64(1000);
      const encryptedInput = await input.encrypt();

      await this.token
        .connect(this.holder)
        ["$_mint(address,bytes32,bytes)"](this.holder, encryptedInput.handles[0], encryptedInput.inputProof);
    });
    it("to a user", async function () {
      // Reencrypt with holder's key
      const balanceOfHandleHolder = await this.token.balanceOf(this.holder);
      await expect(
        reencryptEuint64(this.holder, this.fhevm, balanceOfHandleHolder, this.token.target),
      ).to.eventually.equal(1000);
    });

    it("should increase total supply", async function () {
      const totalSupplyHandle = await this.token.totalSupply();
      await expect(reencryptEuint64(this.holder, this.fhevm, totalSupplyHandle, this.token.target)).to.eventually.equal(
        1000,
      );
    });
  });

  describe("transfer", function () {
    beforeEach(async function () {
      const input = this.fhevm.createEncryptedInput(this.token.target, this.holder.address);
      input.add64(1000);
      const encryptedInput = await input.encrypt();

      await this.token
        .connect(this.holder)
        ["$_mint(address,bytes32,bytes)"](this.holder, encryptedInput.handles[0], encryptedInput.inputProof);
    });

    for (const asSender of [true, false]) {
      describe(asSender ? "as sender" : "as operator", function () {
        beforeEach(async function () {
          if (!asSender) {
            const timestamp = (await ethers.provider.getBlock("latest"))!.timestamp + 100;
            await this.token.$_setOperator(this.holder, this.operator, timestamp);
          }
        });

        let sufficientBalance: boolean;

        it("sufficient balance", async function () {
          sufficientBalance = true;
        });

        it("insufficient balance", async function () {
          sufficientBalance = false;
        });

        afterEach(async function () {
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
            await expect(this.token.isOperator(this.holder, this.operator)).to.eventually.be.true;
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

          // const transferAmountHandle = transferEvent.args[2];
          const holderBalanceHandle = await this.token.balanceOf(this.holder);
          const recipientBalanceHandle = await this.token.balanceOf(this.recipient);

          // await expect(
          //   reencryptEuint64(this.holder, this.fhevm, transferAmountHandle, this.token.target),
          // ).to.eventually.equal(transferAmount);
          // await expect(
          //   reencryptEuint64(this.recipient, this.fhevm, transferAmountHandle, this.token.target),
          // ).to.eventually.equal(transferAmount);

          await expect(
            reencryptEuint64(this.holder, this.fhevm, holderBalanceHandle, this.token.target),
          ).to.eventually.equal(1000 - (sufficientBalance ? transferAmount : 0));
          await expect(
            reencryptEuint64(this.recipient, this.fhevm, recipientBalanceHandle, this.token.target),
          ).to.eventually.equal(sufficientBalance ? transferAmount : 0);
        });
      });
    }
  });
});
/* eslint-enable no-unexpected-multiline */
