import { INTERFACE_IDS, INVALID_ID } from '../../../helpers/interface';
import { expect } from 'chai';
import { ethers } from 'hardhat';

const name = 'ConfidentialFungibleToken';
const symbol = 'CFT';
const uri = 'https://example.com/metadata';

describe('ERC7984Metadata', function () {
  beforeEach(async function () {
    this.token = await ethers.deployContract('$ERC7984MetadataMock', [name, symbol, uri]);
    await expect(this.token.contractURI()).to.eventually.equal(uri);
  });

  describe('_setContractURI', function () {
    it('sets the contract URI', async function () {
      await this.token.$_setContractURI('new URI');
      await expect(this.token.contractURI()).to.eventually.equal('new URI');
    });

    it('emits a ContractURIUpdated event', async function () {
      await expect(this.token.$_setContractURI(uri)).to.emit(this.token, 'ContractURIUpdated');
    });
  });

  describe('ERC165', function () {
    it('supports IERC7984Metadata', async function () {
      await expect(this.token.supportsInterface(INTERFACE_IDS.ERC7984Metadata)).to.eventually.be.true;
    });

    it('supports IERC7984', async function () {
      await expect(this.token.supportsInterface(INTERFACE_IDS.ERC7984)).to.eventually.be.true;
    });

    it('does not support invalid interface', async function () {
      await expect(this.token.supportsInterface(INVALID_ID)).to.eventually.be.false;
    });
  });
});
