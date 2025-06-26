const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const { VALUE_SIZES } = require('../../../scripts/generate/templates/CheckpointsConfidential.opts');

describe('CheckpointsConfidential', function () {
  for (const size of VALUE_SIZES) {
    describe(`TraceEuint${size}`, function () {
      const fixture = async () => {
        const mock = await ethers.deployContract('$CheckpointsConfidential');
        const methods = {
          at: (...args) => mock.getFunction(`$at_CheckpointsConfidential_TraceEuint${size}`)(0, ...args),
          latest: (...args) => mock.getFunction(`$latest_CheckpointsConfidential_TraceEuint${size}`)(0, ...args),
          latestCheckpoint: (...args) =>
            mock.getFunction(`$latestCheckpoint_CheckpointsConfidential_TraceEuint${size}`)(0, ...args),
          length: (...args) => mock.getFunction(`$length_CheckpointsConfidential_TraceEuint${size}`)(0, ...args),
          push: (...args) =>
            mock.getFunction(`$push_CheckpointsConfidential_TraceEuint${size}_euint${size}(uint256,uint256,uint256)`)(
              0,
              ...args,
            ),
          lowerLookup: (...args) =>
            mock.getFunction(`$lowerLookup_CheckpointsConfidential_TraceEuint${size}(uint256,uint256)`)(0, ...args),
          upperLookup: (...args) =>
            mock.getFunction(`$upperLookup_CheckpointsConfidential_TraceEuint${size}(uint256,uint256)`)(0, ...args),
          upperLookupRecent: (...args) =>
            mock.getFunction(`$upperLookupRecent_CheckpointsConfidential_TraceEuint${size}(uint256,uint256)`)(
              0,
              ...args,
            ),
        };

        return { mock, methods };
      };

      beforeEach(async function () {
        Object.assign(this, await loadFixture(fixture));
      });

      describe('without checkpoints', function () {
        it('at zero reverts', async function () {
          // Reverts with array out of bound access, which is unspecified
          await expect(this.methods.at(0)).to.be.reverted;
        });

        it('returns zero as latest value', async function () {
          await expect(this.methods.latest()).to.eventually.equal(0n);

          const ckpt = await this.methods.latestCheckpoint();
          expect(ckpt[0]).to.be.false;
          expect(ckpt[1]).to.equal(0n);
          expect(ckpt[2]).to.equal(0n);
        });

        it('lookup returns 0', async function () {
          await expect(this.methods.lowerLookup(0)).to.eventually.equal(0n);
          await expect(this.methods.upperLookup(0)).to.eventually.equal(0n);
          await expect(this.methods.upperLookupRecent(0)).to.eventually.equal(0n);
        });
      });

      describe('with checkpoints', function () {
        beforeEach('pushing checkpoints', async function () {
          this.checkpoints = [
            { key: 2n, value: 17n },
            { key: 3n, value: 42n },
            { key: 5n, value: 101n },
            { key: 7n, value: 23n },
            { key: 11n, value: 99n },
          ];
          for (const { key, value } of this.checkpoints) {
            await this.methods.push(key, value);
          }
        });

        it('at keys', async function () {
          for (const [index, { key, value }] of this.checkpoints.entries()) {
            await expect(this.methods.at(index)).to.eventually.deep.equal([key, value]);
          }
        });

        it('length', async function () {
          await expect(this.methods.length()).to.eventually.equal(this.checkpoints.length);
        });

        it('returns latest value', async function () {
          const latest = this.checkpoints.at(-1);
          await expect(this.methods.latest()).to.eventually.equal(latest.value);
          await expect(this.methods.latestCheckpoint()).to.eventually.deep.equal([true, latest.key, latest.value]);
        });

        it('cannot push values in the past', async function () {
          await expect(this.methods.push(this.checkpoints.at(-1).key - 1n, 0n)).to.be.revertedWithCustomError(
            this.mock,
            'CheckpointUnorderedInsertion',
          );
        });

        it('can update last value', async function () {
          const newValue = 42n;

          // check length before the update
          await expect(this.methods.length()).to.eventually.equal(this.checkpoints.length);

          // update last key
          await this.methods.push(this.checkpoints.at(-1).key, newValue);
          await expect(this.methods.latest()).to.eventually.equal(newValue);

          // check that length did not change
          await expect(this.methods.length()).to.eventually.equal(this.checkpoints.length);
        });

        it('lower lookup', async function () {
          for (let i = 0; i < 14; ++i) {
            const value = this.checkpoints.find(x => i <= x.key)?.value || 0n;

            await expect(this.methods.lowerLookup(i)).to.eventually.equal(value);
          }
        });

        it('upper lookup & upperLookupRecent', async function () {
          for (let i = 0; i < 14; ++i) {
            const value = this.checkpoints.findLast(x => i >= x.key)?.value || 0n;

            await expect(this.methods.upperLookup(i)).to.eventually.equal(value);
            await expect(this.methods.upperLookupRecent(i)).to.eventually.equal(value);
          }
        });

        it('upperLookupRecent with more than 5 checkpoints', async function () {
          const moreCheckpoints = [
            { key: 12n, value: 22n },
            { key: 13n, value: 131n },
            { key: 17n, value: 45n },
            { key: 19n, value: 31452n },
            { key: 21n, value: 0n },
          ];
          const allCheckpoints = [].concat(this.checkpoints, moreCheckpoints);

          for (const { key, value } of moreCheckpoints) {
            await this.methods.push(key, value);
          }

          for (let i = 0; i < 25; ++i) {
            const value = allCheckpoints.findLast(x => i >= x.key)?.value || 0n;
            await expect(this.methods.upperLookup(i)).to.eventually.equal(value);
            await expect(this.methods.upperLookupRecent(i)).to.eventually.equal(value);
          }
        });
      });
    });
  }
});
