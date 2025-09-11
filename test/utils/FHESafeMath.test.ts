import { FHESafeMathMock } from '../../types/contracts/mocks/utils/FHESafeMathMock';
import { callAndGetResult } from '../helpers/event';
import { FhevmType } from '@fhevm/hardhat-plugin';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

const MaxUint64 = BigInt('0xffffffffffffffff');
const handleCreatedSignature = 'HandleCreated(bytes32)';
const resultComputedSignature = 'ResultComputed(bytes32,bytes32)';
let fheSafeMath: FHESafeMathMock;
let account: HardhatEthersSigner;

describe('FHESafeMath', function () {
  beforeEach(async function () {
    fheSafeMath = (await ethers.deployContract('FHESafeMathMock')) as any as FHESafeMathMock;
    [account] = await ethers.getSigners();
  });

  describe('try increase', function () {
    for (const args of [
      // a + b = c & success
      [undefined, undefined, undefined, true],
      [undefined, 0, 0, true],
      [undefined, 1, 1, true],
      [0, undefined, 0, true],
      [1, undefined, 1, true],
      [MaxUint64, 0, MaxUint64, true],
      [0, MaxUint64, MaxUint64, true],
      [MaxUint64, 1, MaxUint64, false],
      [1, MaxUint64, 1, false],
    ]) {
      it(`${args[0]} + ${args[1]} = ${args[2]} & ${args[3] ? 'success' : 'failure'}`, async function () {
        const [a, b, c, expected] = args as [number, number, number, boolean];
        const [handleA] =
          a !== undefined
            ? await callAndGetResult(fheSafeMath.createHandle(a), handleCreatedSignature)
            : [ethers.ZeroHash];
        const [handleB] =
          b !== undefined
            ? await callAndGetResult(fheSafeMath.createHandle(b), handleCreatedSignature)
            : [ethers.ZeroHash];
        const [success, updated] = await callAndGetResult(
          fheSafeMath.tryIncrease(handleA, handleB),
          resultComputedSignature,
        );
        await expect(fhevm.userDecryptEbool(success, fheSafeMath.target, account)).to.eventually.equal(expected);
        if (c !== undefined) {
          await expect(
            fhevm.userDecryptEuint(FhevmType.euint64, updated, fheSafeMath.target, account),
          ).to.eventually.equal(c);
        } else {
          expect(updated).to.eq(ethers.ZeroHash);
        }
      });
    }
  });

  describe('try decrease', function () {
    for (const args of [
      // a - b = c & success
      [undefined, undefined, undefined, true],
      [undefined, 0, undefined, true],
      [0, undefined, 0, true],
      [1, 1, 0, true],
      [undefined, 1, undefined, false],
      [0, 1, 0, false],
    ]) {
      it(`${args[0]} - ${args[1]} = ${args[2]} & ${args[3] ? 'success' : 'failure'}`, async function () {
        const [a, b, c, expected] = args as [number, number, number, boolean];
        const [handleA] =
          a !== undefined
            ? await callAndGetResult(fheSafeMath.createHandle(a), handleCreatedSignature)
            : [ethers.ZeroHash];
        const [handleB] =
          b !== undefined
            ? await callAndGetResult(fheSafeMath.createHandle(b), handleCreatedSignature)
            : [ethers.ZeroHash];
        const [success, updated] = await callAndGetResult(
          fheSafeMath.tryDecrease(handleA, handleB),
          resultComputedSignature,
        );
        if (c !== undefined) {
          await expect(
            fhevm.userDecryptEuint(FhevmType.euint64, updated, fheSafeMath.target, account),
          ).to.eventually.equal(c);
        } else {
          expect(updated).to.eq(ethers.ZeroHash);
        }
        await expect(fhevm.userDecryptEbool(success, fheSafeMath.target, account)).to.eventually.equal(expected);
      });
    }
  });
});
