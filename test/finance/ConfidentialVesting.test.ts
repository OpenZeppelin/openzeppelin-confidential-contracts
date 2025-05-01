import { time } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import hre, { ethers } from "hardhat";

import { awaitAllDecryptionResults, initGateway } from "../_template/asyncDecrypt";
import { createInstance } from "../_template/instance";
import { reencryptEuint64 } from "../_template/reencrypt";
import { impersonate } from "../helpers/accounts";

const name = "ConfidentialFungibleToken";
const symbol = "CFT";
const uri = "https://example.com/metadata";

describe("ConfidentialVesting", function () {
  beforeEach(async function () {
    const accounts = await ethers.getSigners();
    const [holder, recipient, operator] = accounts;

    const token = await ethers.deployContract("$ConfidentialFungibleTokenMock", [name, symbol, uri]);
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

    this.vesting = await ethers.deployContract("$ConfidentialVestingMock", [this.token]);
    await this.token.$_setOperator(this.holder, this.vesting, Math.round(Date.now() / 1000) + 100);
  });

  it("create vesting", async function () {
    const input = this.fhevm.createEncryptedInput(this.vesting.target, this.holder.address);
    input.add64(500);
    const totalVestingAmount = await input.encrypt();

    const input2 = this.fhevm.createEncryptedInput(this.vesting.target, this.holder.address);
    input2.add64(5);
    const vestingPerSecond = await input2.encrypt();

    await this.vesting
      .connect(this.holder)
      .createVestingStream(
        Math.round(Date.now() / 1000) + 10,
        this.recipient.address,
        totalVestingAmount.handles[0],
        vestingPerSecond.handles[0],
        totalVestingAmount.inputProof,
        vestingPerSecond.inputProof,
      );
  });

  it("claim from vesting stream", async function () {
    const vestingStartTime = (await time.latest()) + 10;
    const input = this.fhevm.createEncryptedInput(this.vesting.target, this.holder.address);
    input.add64(500);
    const totalVestingAmount = await input.encrypt();

    const input2 = this.fhevm.createEncryptedInput(this.vesting.target, this.holder.address);
    input2.add64(5);
    const vestingPerSecond = await input2.encrypt();

    await this.vesting
      .connect(this.holder)
      .createVestingStream(
        vestingStartTime,
        this.recipient.address,
        totalVestingAmount.handles[0],
        vestingPerSecond.handles[0],
        totalVestingAmount.inputProof,
        vestingPerSecond.inputProof,
      );

    await time.setNextBlockTimestamp(vestingStartTime + 10);
    await this.vesting.connect(this.recipient).claim(1);

    let recipientBalanceHandle = await this.token.balanceOf(this.recipient);
    await expect(
      reencryptEuint64(this.recipient, this.fhevm, recipientBalanceHandle, this.token.target),
    ).to.eventually.equal(50);

    await time.setNextBlockTimestamp(vestingStartTime + 11);
    await this.vesting.connect(this.recipient).claim(1);

    recipientBalanceHandle = await this.token.balanceOf(this.recipient);
    await expect(
      reencryptEuint64(this.recipient, this.fhevm, recipientBalanceHandle, this.token.target),
    ).to.eventually.equal(55);
  });
});
