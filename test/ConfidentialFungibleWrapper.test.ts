import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";

import { awaitAllDecryptionResults, initGateway } from "./_template/asyncDecrypt";
import { createInstance } from "./_template/instance";
import { reencryptEuint64 } from "./_template/reencrypt";

const name = "ConfidentialFungibleToken";
const symbol = "CFT";
const uri = "https://example.com/metadata";

/* eslint-disable no-unexpected-multiline */
describe.only("ConfidentialFungibleTokenWrapper", function () {
  const fixture = async () => {
    const accounts = await ethers.getSigners();
    const [holder, recipient, operator] = accounts;

    const token = await ethers.deployContract("ERC20Mock", ["Public Token", "PT"]);
    const wrapper = await ethers.deployContract("ConfidentialFungibleTokenERC20WrapperMock", [
      token,
      name,
      symbol,
      uri,
    ]);

    return { accounts: accounts.slice(3), holder, recipient, token, operator, wrapper };
  };

  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
    this.fhevm = await createInstance();

    await this.token.$_mint(this.holder.address, ethers.parseUnits("1000", 18));
    await this.token.connect(this.holder).approve(this.wrapper, ethers.MaxUint256);
  });

  describe("Wrap", async function () {
    it("via transfer from", async function () {
      const amountToWrap = ethers.parseUnits("100", 18);
      await this.wrapper.connect(this.holder).wrap(this.holder.address, amountToWrap);
    });

    it("via ERC1363 callback", async function () {
      const amountToWrap = ethers.parseUnits("100", 18);
      await this.token.connect(this.holder).transferAndCall(this.wrapper, amountToWrap);
    });

    afterEach(async function () {
      await expect(this.token.balanceOf(this.holder)).to.eventually.equal(ethers.parseUnits("900", 18));

      const wrappedBalanceHandle = await this.wrapper.balanceOf(this.holder.address);
      await expect(
        reencryptEuint64(this.holder, this.fhevm, wrappedBalanceHandle, this.wrapper.target),
      ).to.eventually.equal(ethers.parseUnits("100", 9));
    });
  });

  describe("Unwrap", async function () {
    beforeEach(async function () {
      const amountToWrap = ethers.parseUnits("100", 18);
      await this.token.connect(this.holder).transferAndCall(this.wrapper, amountToWrap);

      await initGateway();
    });

    it("less than balance", async function () {
      const withdrawalAmount = ethers.parseUnits("10", 9);
      const input = this.fhevm.createEncryptedInput(this.wrapper.target, this.holder.address);
      input.add64(withdrawalAmount);
      const encryptedInput = await input.encrypt();

      await this.wrapper
        .connect(this.holder)
        ["unwrap(address,address,bytes32,bytes)"](
          this.holder,
          this.holder,
          encryptedInput.handles[0],
          encryptedInput.inputProof,
        );

      // wait for gateway to process the request
      await awaitAllDecryptionResults();

      await expect(this.token.balanceOf(this.holder)).to.eventually.equal(
        withdrawalAmount * 10n ** 9n + ethers.parseUnits("900", 18),
      );
    });

    it("to invalid recipient", async function () {
      const withdrawalAmount = ethers.parseUnits("10", 9);
      const input = this.fhevm.createEncryptedInput(this.wrapper.target, this.holder.address);
      input.add64(withdrawalAmount);
      const encryptedInput = await input.encrypt();

      await expect(
        this.wrapper
          .connect(this.holder)
          ["unwrap(address,address,bytes32,bytes)"](
            this.holder,
            ethers.ZeroAddress,
            encryptedInput.handles[0],
            encryptedInput.inputProof,
          ),
      )
        .to.be.revertedWithCustomError(this.wrapper, "InvalidTokenRecipient")
        .withArgs(ethers.ZeroAddress);
    });

    it("more than balance", async function () {
      const withdrawalAmount = ethers.parseUnits("1001", 9);
      const input = this.fhevm.createEncryptedInput(this.wrapper.target, this.holder.address);
      input.add64(withdrawalAmount);
      const encryptedInput = await input.encrypt();

      await this.wrapper
        .connect(this.holder)
        ["unwrap(address,address,bytes32,bytes)"](
          this.holder,
          this.holder,
          encryptedInput.handles[0],
          encryptedInput.inputProof,
        );

      await awaitAllDecryptionResults();
      await expect(this.token.balanceOf(this.holder)).to.eventually.equal(ethers.parseUnits("900", 18));
    });
  });
});
/* eslint-disable no-unexpected-multiline */
