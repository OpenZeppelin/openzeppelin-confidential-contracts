import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";

import { createInstance } from "./_template/instance";
import { reencryptEuint64 } from "./_template/reencrypt";

const name = "ConfidentialFungibleToken";
const symbol = "CFT";
const uri = "https://example.com/metadata";

describe.only("ConfidentialFungibleToken", function () {
  const fixture = async () => {
    const accounts = await ethers.getSigners();
    const [holder, recipient] = accounts;

    const token = await ethers.deployContract("ConfidentialFungibleTokenMock", [name, symbol, uri]);

    return { accounts: accounts.slice(2), holder, recipient, token };
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

    it("to recipient", async function () {
      const input = this.fhevm.createEncryptedInput(this.token.target, this.holder.address);
      input.add64(400);
      const encryptedInput = await input.encrypt();

      await this.token
        .connect(this.holder)
        ["confidentialTransfer(address,bytes32,bytes)"](
          this.recipient.address,
          encryptedInput.handles[0],
          encryptedInput.inputProof,
        );

      const holderBalanceHandle = await this.token.balanceOf(this.holder);
      const recipientBalanceHandle = await this.token.balanceOf(this.recipient);

      await expect(
        reencryptEuint64(this.holder, this.fhevm, holderBalanceHandle, this.token.target),
      ).to.eventually.equal(600);

      await expect(
        reencryptEuint64(this.recipient, this.fhevm, recipientBalanceHandle, this.token.target),
      ).to.eventually.equal(400);

      await expect(
        reencryptEuint64(this.holder, this.fhevm, recipientBalanceHandle, this.token.target),
      ).to.be.rejectedWith("User is not authorized to reencrypt this handle!");
    });
  });
});
