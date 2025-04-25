import { expect } from "chai";
import { ethers, network } from "hardhat";

import { awaitAllDecryptionResults, initGateway } from "../asyncDecrypt";
import { createInstance } from "../instance";
import { getSigners, initSigners } from "../signers";
import { bigIntToBytes64, bigIntToBytes128, bigIntToBytes256 } from "../utils";

describe.skip("TestAsyncDecrypt", function () {
  before(async function () {
    await initSigners();
    this.signers = await getSigners();
    await initGateway();
  });

  beforeEach(async function () {
    const contractFactory = await ethers.getContractFactory("TestAsyncDecrypt");
    this.contract = await contractFactory.connect(this.signers.alice).deploy();
    await this.contract.waitForDeployment();
    this.contractAddress = await this.contract.getAddress();
    this.fhevm = await createInstance();
  });

  it("test async decrypt bool", async function () {
    const tx2 = await this.contract.connect(this.signers.carol).requestBool();
    await tx2.wait();
    await awaitAllDecryptionResults();
    const y = await this.contract.yBool();
    expect(y).to.equal(true);
  });

  it("test async decrypt bool trustless", async function () {
    const tx2 = await this.contract.requestBoolTrustless();
    await tx2.wait();
    await awaitAllDecryptionResults();
    const y = await this.contract.yBool();
    expect(y).to.equal(true);
  });

  it("test async decrypt bool would fail if maxTimestamp is above 1 day", async function () {
    await expect(this.contract.connect(this.signers.carol).requestBoolAboveDelay()).to.be.revertedWith(
      "maxTimestamp exceeded MAX_DELAY",
    );
  });

  it("test async decrypt uint4", async function () {
    const tx2 = await this.contract.connect(this.signers.carol).requestUint4();
    await tx2.wait();
    await awaitAllDecryptionResults();
    const y = await this.contract.yUint4();
    expect(y).to.equal(4);
  });

  it("test async decrypt uint8", async function () {
    const tx2 = await this.contract.connect(this.signers.carol).requestUint8();
    await tx2.wait();
    await awaitAllDecryptionResults();
    const y = await this.contract.yUint8();
    expect(y).to.equal(42);
  });

  it("test async decrypt uint16", async function () {
    const tx2 = await this.contract.connect(this.signers.carol).requestUint16();
    await tx2.wait();
    await awaitAllDecryptionResults();
    const y = await this.contract.yUint16();
    expect(y).to.equal(16);
  });

  it("test async decrypt uint32", async function () {
    const tx2 = await this.contract.connect(this.signers.carol).requestUint32(5, 15);
    await tx2.wait();
    await awaitAllDecryptionResults();
    const y = await this.contract.yUint32();
    expect(y).to.equal(52); // 5+15+32
  });

  it("test async decrypt uint64", async function () {
    const tx2 = await this.contract.connect(this.signers.carol).requestUint64();
    await tx2.wait();
    await awaitAllDecryptionResults();
    const y = await this.contract.yUint64();
    expect(y).to.equal(18446744073709551600n);
  });

  it("test async decrypt uint128", async function () {
    const tx2 = await this.contract.connect(this.signers.carol).requestUint128();
    await tx2.wait();
    await awaitAllDecryptionResults();
    const y = await this.contract.yUint128();
    expect(y).to.equal(1267650600228229401496703205443n);
  });

  it("test async decrypt uint128 non-trivial", async function () {
    const inputAlice = this.fhevm.createEncryptedInput(this.contractAddress, this.signers.alice.address);
    inputAlice.add128(184467440737095500429401496n);
    const encryptedAmount = await inputAlice.encrypt();
    const tx = await this.contract.requestUint128NonTrivial(encryptedAmount.handles[0], encryptedAmount.inputProof);
    await tx.wait();
    await awaitAllDecryptionResults();
    const y = await this.contract.yUint128();
    expect(y).to.equal(184467440737095500429401496n);
  });

  it("test async decrypt uint256", async function () {
    const tx2 = await this.contract.connect(this.signers.carol).requestUint256();
    await tx2.wait();
    await awaitAllDecryptionResults();
    const y = await this.contract.yUint256();
    expect(y).to.equal(27606985387162255149739023449108101809804435888681546220650096895197251n);
  });

  it("test async decrypt uint256 non-trivial", async function () {
    const inputAlice = this.fhevm.createEncryptedInput(this.contractAddress, this.signers.alice.address);
    inputAlice.add256(6985387162255149739023449108101809804435888681546n);
    const encryptedAmount = await inputAlice.encrypt();
    const tx = await this.contract.requestUint256NonTrivial(encryptedAmount.handles[0], encryptedAmount.inputProof);
    await tx.wait();
    await awaitAllDecryptionResults();
    const y = await this.contract.yUint256();
    expect(y).to.equal(6985387162255149739023449108101809804435888681546n);
  });

  it("test async decrypt address", async function () {
    const tx2 = await this.contract.connect(this.signers.carol).requestAddress();
    await tx2.wait();
    await awaitAllDecryptionResults();
    const y = await this.contract.yAddress();
    expect(y).to.equal("0x8ba1f109551bD432803012645Ac136ddd64DBA72");
  });

  it("test async decrypt several addresses", async function () {
    const tx2 = await this.contract.connect(this.signers.carol).requestSeveralAddresses();
    await tx2.wait();
    await awaitAllDecryptionResults();
    const y = await this.contract.yAddress();
    const y2 = await this.contract.yAddress2();
    expect(y).to.equal("0x8ba1f109551bD432803012645Ac136ddd64DBA72");
    expect(y2).to.equal("0xf48b8840387ba3809DAE990c930F3b4766A86ca3");
  });

  it("test async decrypt mixed", async function () {
    const tx2 = await this.contract.connect(this.signers.carol).requestMixed(5, 15);
    await tx2.wait();
    await awaitAllDecryptionResults();
    const yB = await this.contract.yBool();
    expect(yB).to.equal(true);
    let y = await this.contract.yUint4();
    expect(y).to.equal(4);
    y = await this.contract.yUint8();
    expect(y).to.equal(42);
    y = await this.contract.yUint16();
    expect(y).to.equal(16);
    const yAdd = await this.contract.yAddress();
    expect(yAdd).to.equal("0x8ba1f109551bD432803012645Ac136ddd64DBA72");
    y = await this.contract.yUint32();
    expect(y).to.equal(52); // 5+15+32
    y = await this.contract.yUint64();
    expect(y).to.equal(18446744073709551600n);
  });

  it("test async decrypt uint64 non-trivial", async function () {
    const inputAlice = this.fhevm.createEncryptedInput(this.contractAddress, this.signers.alice.address);
    inputAlice.add64(18446744073709550042n);
    const encryptedAmount = await inputAlice.encrypt();
    const tx = await this.contract.requestUint64NonTrivial(encryptedAmount.handles[0], encryptedAmount.inputProof);
    await tx.wait();
    await awaitAllDecryptionResults();
    const y = await this.contract.yUint64();
    expect(y).to.equal(18446744073709550042n);
  });

  it("test async decrypt ebytes64 trivial", async function () {
    const tx = await this.contract.requestEbytes64Trivial("0x78685689");
    await tx.wait();
    await awaitAllDecryptionResults();
    const y = await this.contract.yBytes64();
    expect(y).to.equal(ethers.toBeHex(BigInt("0x78685689"), 64));
  });

  it("test async decrypt ebytes64 non-trivial", async function () {
    const inputAlice = this.fhevm.createEncryptedInput(this.contractAddress, this.signers.alice.address);
    inputAlice.addBytes64(
      bigIntToBytes64(98870780878070870878787887072921111299111111000000292928818818818818221112111n),
    );
    const encryptedAmount = await inputAlice.encrypt();
    const tx = await this.contract.requestEbytes64NonTrivial(encryptedAmount.handles[0], encryptedAmount.inputProof);
    await tx.wait();
    await awaitAllDecryptionResults();
    const y = await this.contract.yBytes64();
    expect(y).to.equal(
      ethers.toBeHex(98870780878070870878787887072921111299111111000000292928818818818818221112111n, 64),
    );
  });

  it("test async decrypt ebytes128 trivial", async function () {
    const tx = await this.contract.requestEbytes128Trivial(
      "0x8701d11594415047dfac2d9cb87e6631df5a735a2f364fba1511fa7b812dfad2972b809b80ff25ec19591a598081af357cba384cf5aa8e085678ff70bc55faee",
    );
    await tx.wait();
    await awaitAllDecryptionResults();
    const y = await this.contract.yBytes128();
    expect(y).to.equal(
      ethers.toBeHex(
        BigInt(
          "0x8701d11594415047dfac2d9cb87e6631df5a735a2f364fba1511fa7b812dfad2972b809b80ff25ec19591a598081af357cba384cf5aa8e085678ff70bc55faee",
        ),
        128,
      ),
    );
  });

  it("test async decrypt ebytes128 non-trivial", async function () {
    const inputAlice = this.fhevm.createEncryptedInput(this.contractAddress, this.signers.alice.address);
    inputAlice.addBytes128(
      bigIntToBytes128(
        9887078087807087087878788707292111129911111100000029292881881881881822111211198870780878070870878787887072921111299111111000000292928818818818818221112111n,
      ),
    );
    const encryptedAmount = await inputAlice.encrypt();
    const tx = await this.contract.requestEbytes128NonTrivial(encryptedAmount.handles[0], encryptedAmount.inputProof);
    await tx.wait();
    await awaitAllDecryptionResults();
    const y = await this.contract.yBytes128();
    expect(y).to.equal(
      ethers.toBeHex(
        9887078087807087087878788707292111129911111100000029292881881881881822111211198870780878070870878787887072921111299111111000000292928818818818818221112111n,
        128,
      ),
    );
  });

  it("test async decrypt ebytes256 trivial", async function () {
    const tx = await this.contract.requestEbytes256Trivial("0x78685689");
    await tx.wait();
    await awaitAllDecryptionResults();
    const y = await this.contract.yBytes256();
    expect(y).to.equal(ethers.toBeHex(BigInt("0x78685689"), 256));
  });

  it("test async decrypt ebytes256 non-trivial", async function () {
    const inputAlice = this.fhevm.createEncryptedInput(this.contractAddress, this.signers.alice.address);
    inputAlice.addBytes256(bigIntToBytes256(18446744073709550022n));
    const encryptedAmount = await inputAlice.encrypt();
    const tx = await this.contract.requestEbytes256NonTrivial(encryptedAmount.handles[0], encryptedAmount.inputProof);
    await tx.wait();
    await awaitAllDecryptionResults();
    const y = await this.contract.yBytes256();
    expect(y).to.equal(ethers.toBeHex(18446744073709550022n, 256));
  });

  it("test async decrypt ebytes256 non-trivial with snapshot [skip-on-coverage]", async function () {
    if (network.name === "hardhat") {
      // calling evm_snapshot is possible only in mocked mode
      this.snapshotId = await ethers.provider.send("evm_snapshot");
      const inputAlice = this.fhevm.createEncryptedInput(this.contractAddress, this.signers.alice.address);
      inputAlice.addBytes256(bigIntToBytes256(18446744073709550022n));
      const encryptedAmount = await inputAlice.encrypt();
      const tx = await this.contract.requestEbytes256NonTrivial(encryptedAmount.handles[0], encryptedAmount.inputProof);
      await tx.wait();
      await awaitAllDecryptionResults();
      const y = await this.contract.yBytes256();
      expect(y).to.equal(ethers.toBeHex(18446744073709550022n, 256));

      await ethers.provider.send("evm_revert", [this.snapshotId]);
      const inputAlice2 = this.fhevm.createEncryptedInput(this.contractAddress, this.signers.alice.address);
      inputAlice2.addBytes256(bigIntToBytes256(424242n));
      const encryptedAmount2 = await inputAlice2.encrypt();
      const tx2 = await this.contract.requestEbytes256NonTrivial(
        encryptedAmount2.handles[0],
        encryptedAmount2.inputProof,
      );
      await tx2.wait();
      await awaitAllDecryptionResults();
      const y2 = await this.contract.yBytes256();
      expect(y2).to.equal(ethers.toBeHex(424242n, 256));
    }
  });

  it("test async decrypt mixed with ebytes256", async function () {
    const inputAlice = this.fhevm.createEncryptedInput(this.contractAddress, this.signers.alice.address);
    inputAlice.addBytes256(bigIntToBytes256(18446744073709550032n));
    const encryptedAmount = await inputAlice.encrypt();
    const tx = await this.contract.requestMixedBytes256(encryptedAmount.handles[0], encryptedAmount.inputProof);
    await tx.wait();
    await awaitAllDecryptionResults();
    const y = await this.contract.yBytes256();
    expect(y).to.equal(ethers.toBeHex(18446744073709550032n, 256));
    const y2 = await this.contract.yBytes64();
    expect(y2).to.equal(ethers.toBeHex(BigInt("0xaaff42"), 64));
    const yb = await this.contract.yBool();
    expect(yb).to.equal(true);
    const yAdd = await this.contract.yAddress();
    expect(yAdd).to.equal("0x8ba1f109551bD432803012645Ac136ddd64DBA72");
  });

  it("test async decrypt ebytes256 non-trivial trustless", async function () {
    const inputAlice = this.fhevm.createEncryptedInput(await this.contract.getAddress(), this.signers.alice.address);
    inputAlice.addBytes256(bigIntToBytes256(18446744073709550022n));
    const encryptedAmount = await inputAlice.encrypt();
    const tx = await this.contract.requestEbytes256NonTrivialTrustless(
      encryptedAmount.handles[0],
      encryptedAmount.inputProof,
    );
    await tx.wait();
    await awaitAllDecryptionResults();
    const y = await this.contract.yBytes256();
    expect(y).to.equal(ethers.toBeHex(18446744073709550022n, 256));
  });

  it("test async decrypt mixed with ebytes256 trustless", async function () {
    const inputAlice = this.fhevm.createEncryptedInput(await this.contract.getAddress(), this.signers.alice.address);
    inputAlice.addBytes256(bigIntToBytes256(18446744073709550032n));
    const encryptedAmount = await inputAlice.encrypt();
    const tx = await this.contract.requestMixedBytes256Trustless(
      encryptedAmount.handles[0],
      encryptedAmount.inputProof,
    );
    await tx.wait();
    await awaitAllDecryptionResults();
    const y = await this.contract.yBytes256();
    expect(y).to.equal(ethers.toBeHex(18446744073709550032n, 256));
    const yb = await this.contract.yBool();
    expect(yb).to.equal(true);
    const yAdd = await this.contract.yAddress();
    expect(yAdd).to.equal("0x8ba1f109551bD432803012645Ac136ddd64DBA72");
  });
});
