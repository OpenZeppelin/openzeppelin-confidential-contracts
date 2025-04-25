import { expect } from "chai";
import { network } from "hardhat";

import { createInstance } from "../instance";
import { reencryptEuint64 } from "../reencrypt";
import { getSigners, initSigners } from "../signers";
import { debug } from "../utils";
import { deployConfidentialERC20Fixture } from "./ConfidentialERC20.fixture";

describe.skip("ConfidentialERC20", function () {
  before(async function () {
    await initSigners();
    this.signers = await getSigners();
  });

  beforeEach(async function () {
    const contract = await deployConfidentialERC20Fixture();
    this.contractAddress = await contract.getAddress();
    this.erc20 = contract;
    this.fhevm = await createInstance();
  });

  it("should mint the contract", async function () {
    const transaction = await this.erc20.mint(this.signers.alice, 1000);
    await transaction.wait();

    // Reencrypt Alice's balance
    const balanceHandleAlice = await this.erc20.balanceOf(this.signers.alice);
    const balanceAlice = await reencryptEuint64(
      this.signers.alice,
      this.fhevm,
      balanceHandleAlice,
      this.contractAddress,
    );

    expect(balanceAlice).to.equal(1000);

    const totalSupply = await this.erc20.totalSupply();
    expect(totalSupply).to.equal(1000);
  });

  it("should transfer tokens between two users", async function () {
    const transaction = await this.erc20.mint(this.signers.alice, 10000);
    const t1 = await transaction.wait();
    expect(t1?.status).to.eq(1);

    const input = this.fhevm.createEncryptedInput(this.contractAddress, this.signers.alice.address);
    input.add64(1337);
    const encryptedTransferAmount = await input.encrypt();
    const tx = await this.erc20["transfer(address,bytes32,bytes)"](
      this.signers.bob,
      encryptedTransferAmount.handles[0],
      encryptedTransferAmount.inputProof,
    );
    const t2 = await tx.wait();
    expect(t2?.status).to.eq(1);

    // Reencrypt Alice's balance
    const balanceHandleAlice = await this.erc20.balanceOf(this.signers.alice);
    const balanceAlice = await reencryptEuint64(
      this.signers.alice,
      this.fhevm,
      balanceHandleAlice,
      this.contractAddress,
    );
    expect(balanceAlice).to.equal(10000 - 1337);

    // Reencrypt Bob's balance
    const balanceHandleBob = await this.erc20.balanceOf(this.signers.bob);
    const balanceBob = await reencryptEuint64(this.signers.bob, this.fhevm, balanceHandleBob, this.contractAddress);
    expect(balanceBob).to.equal(1337);

    // on the other hand, Bob should be unable to read Alice's balance
    await expect(
      reencryptEuint64(this.signers.bob, this.fhevm, balanceHandleAlice, this.contractAddress),
    ).to.be.rejectedWith("User is not authorized to reencrypt this handle!");

    // and should be impossible to call reencrypt if contractAddress === userAddress
    await expect(
      reencryptEuint64(this.signers.alice, this.fhevm, balanceHandleAlice, this.signers.alice.address),
    ).to.be.rejectedWith("userAddress should not be equal to contractAddress when requesting reencryption!");
  });

  it("should not transfer tokens between two users", async function () {
    const transaction = await this.erc20.mint(this.signers.alice, 1000);
    await transaction.wait();

    const input = this.fhevm.createEncryptedInput(this.contractAddress, this.signers.alice.address);
    input.add64(1337);
    const encryptedTransferAmount = await input.encrypt();
    const tx = await this.erc20["transfer(address,bytes32,bytes)"](
      this.signers.bob,
      encryptedTransferAmount.handles[0],
      encryptedTransferAmount.inputProof,
    );
    await tx.wait();

    const balanceHandleAlice = await this.erc20.balanceOf(this.signers.alice);
    const balanceAlice = await reencryptEuint64(
      this.signers.alice,
      this.fhevm,
      balanceHandleAlice,
      this.contractAddress,
    );
    expect(balanceAlice).to.equal(1000);

    // Reencrypt Bob's balance
    const balanceHandleBob = await this.erc20.balanceOf(this.signers.bob);
    const balanceBob = await reencryptEuint64(this.signers.bob, this.fhevm, balanceHandleBob, this.contractAddress);
    expect(balanceBob).to.equal(0);
  });

  it("should be able to transferFrom only if allowance is sufficient", async function () {
    const transaction = await this.erc20.mint(this.signers.alice, 10000);
    await transaction.wait();

    const inputAlice = this.fhevm.createEncryptedInput(this.contractAddress, this.signers.alice.address);
    inputAlice.add64(1337);
    const encryptedAllowanceAmount = await inputAlice.encrypt();
    const tx = await this.erc20["approve(address,bytes32,bytes)"](
      this.signers.bob,
      encryptedAllowanceAmount.handles[0],
      encryptedAllowanceAmount.inputProof,
    );
    await tx.wait();

    const bobErc20 = this.erc20.connect(this.signers.bob);
    const inputBob1 = this.fhevm.createEncryptedInput(this.contractAddress, this.signers.bob.address);
    inputBob1.add64(1338); // above allowance so next tx should actually not send any token
    const encryptedTransferAmount = await inputBob1.encrypt();
    const tx2 = await bobErc20["transferFrom(address,address,bytes32,bytes)"](
      this.signers.alice,
      this.signers.bob,
      encryptedTransferAmount.handles[0],
      encryptedTransferAmount.inputProof,
    );
    await tx2.wait();

    // Decrypt Alice's balance
    const balanceHandleAlice = await this.erc20.balanceOf(this.signers.alice);
    const balanceAlice = await reencryptEuint64(
      this.signers.alice,
      this.fhevm,
      balanceHandleAlice,
      this.contractAddress,
    );
    expect(balanceAlice).to.equal(10000); // check that transfer did not happen, as expected

    // Decrypt Bob's balance
    const balanceHandleBob = await this.erc20.balanceOf(this.signers.bob);
    const balanceBob = await reencryptEuint64(this.signers.bob, this.fhevm, balanceHandleBob, this.contractAddress);
    expect(balanceBob).to.equal(0); // check that transfer did not happen, as expected

    const inputBob2 = this.fhevm.createEncryptedInput(this.contractAddress, this.signers.bob.address);
    inputBob2.add64(1337); // below allowance so next tx should send token
    const encryptedTransferAmount2 = await inputBob2.encrypt();
    const tx3 = await bobErc20["transferFrom(address,address,bytes32,bytes)"](
      this.signers.alice,
      this.signers.bob,
      encryptedTransferAmount2.handles[0],
      encryptedTransferAmount2.inputProof,
    );
    await tx3.wait();

    // Decrypt Alice's balance
    const balanceHandleAlice2 = await this.erc20.balanceOf(this.signers.alice);
    const balanceAlice2 = await reencryptEuint64(
      this.signers.alice,
      this.fhevm,
      balanceHandleAlice2,
      this.contractAddress,
    );
    expect(balanceAlice2).to.equal(10000 - 1337); // check that transfer did happen this time

    // Decrypt Bob's balance
    const balanceHandleBob2 = await this.erc20.balanceOf(this.signers.bob);
    const balanceBob2 = await reencryptEuint64(this.signers.bob, this.fhevm, balanceHandleBob2, this.contractAddress);
    expect(balanceBob2).to.equal(1337); // check that transfer did happen this time
  });

  it("DEBUG - using debug.decrypt64 for debugging transfer", async function () {
    if (network.name === "hardhat") {
      // using the debug.decryptXX functions is possible only in mocked mode

      const transaction = await this.erc20.mint(this.signers.alice, 1000);
      await transaction.wait();
      const input = this.fhevm.createEncryptedInput(this.contractAddress, this.signers.alice.address);
      input.add64(1337);
      const encryptedTransferAmount = await input.encrypt();
      const tx = await this.erc20["transfer(address,bytes32,bytes)"](
        this.signers.bob,
        encryptedTransferAmount.handles[0],
        encryptedTransferAmount.inputProof,
      );
      await tx.wait();

      const balanceHandleAlice = await this.erc20.balanceOf(this.signers.alice);
      const balanceAlice = await debug.decrypt64(balanceHandleAlice);
      expect(balanceAlice).to.equal(1000);

      // Reencrypt Bob's balance
      const balanceHandleBob = await this.erc20.balanceOf(this.signers.bob);
      const balanceBob = await debug.decrypt64(balanceHandleBob);
      expect(balanceBob).to.equal(0);
    }
  });
});
