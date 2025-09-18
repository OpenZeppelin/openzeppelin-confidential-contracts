const { ethers, fhevm } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const initialSupply = 1000n;

async function fixture() {
  const [holder, recipient, approved] = await ethers.getSigners();

  const token = await ethers.deployContract('$ERC7984RestrictedMock', ['token', 'tk', 'uri']);
  await token['$_mint(address,uint64)'](holder, initialSupply);

  return { holder, recipient, approved, token };
}

describe('ERC7984Restricted', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('restriction management', function () {
    it('returns DEFAULT restriction for new users', async function () {
      await expect(this.token.getRestriction(this.holder)).to.eventually.equal(0); // DEFAULT
    });

    it('allows users with DEFAULT restriction', async function () {
      await expect(this.token.isUserAllowed(this.holder)).to.eventually.equal(true);
    });

    it('allows users with ALLOWED status', async function () {
      await this.token.$_allowUser(this.holder); // Sets to ALLOWED
      await expect(this.token.getRestriction(this.holder)).to.eventually.equal(2); // ALLOWED
      await expect(this.token.isUserAllowed(this.holder)).to.eventually.equal(true);
    });

    it('blocks users with BLOCKED status', async function () {
      await this.token.$_blockUser(this.holder); // Sets to BLOCKED
      await expect(this.token.getRestriction(this.holder)).to.eventually.equal(1); // BLOCKED
      await expect(this.token.isUserAllowed(this.holder)).to.eventually.equal(false);
    });

    it('resets user to DEFAULT restriction', async function () {
      await this.token.$_blockUser(this.holder); // Sets to BLOCKED
      await this.token.$_resetUser(this.holder); // Sets to DEFAULT
      await expect(this.token.getRestriction(this.holder)).to.eventually.equal(0); // DEFAULT
      await expect(this.token.isUserAllowed(this.holder)).to.eventually.equal(true);
    });

    it('emits UserRestrictionUpdated event when restriction changes', async function () {
      await expect(this.token.$_blockUser(this.holder))
        .to.emit(this.token, 'UserRestrictionUpdated')
        .withArgs(this.holder, 1); // BLOCKED

      await expect(this.token.$_allowUser(this.holder))
        .to.emit(this.token, 'UserRestrictionUpdated')
        .withArgs(this.holder, 2); // ALLOWED

      await expect(this.token.$_resetUser(this.holder))
        .to.emit(this.token, 'UserRestrictionUpdated')
        .withArgs(this.holder, 0); // DEFAULT
    });

    it('does not emit event when restriction is unchanged', async function () {
      await this.token.$_blockUser(this.holder); // Sets to BLOCKED
      await expect(this.token.$_blockUser(this.holder)).to.not.emit(this.token, 'UserRestrictionUpdated');
    });
  });

  describe('restricted token operations', function () {
    describe('transfer', function () {
      it('allows transfer when sender and recipient have DEFAULT restriction', async function () {
        await this.token.connect(this.holder).transfer(this.recipient, initialSupply);
      });

      it('allows transfer when sender and recipient are ALLOWED', async function () {
        await this.token.$_allowUser(this.holder); // Sets to ALLOWED
        await this.token.$_allowUser(this.recipient); // Sets to ALLOWED

        await this.token.connect(this.holder).transfer(this.recipient, initialSupply);
      });

      it('reverts when sender is BLOCKED', async function () {
        await this.token.$_blockUser(this.holder); // Sets to BLOCKED

        await expect(this.token.connect(this.holder).transfer(this.recipient, initialSupply))
          .to.be.revertedWithCustomError(this.token, 'UserRestricted')
          .withArgs(this.holder);
      });

      it('reverts when recipient is BLOCKED', async function () {
        await this.token.$_blockUser(this.recipient); // Sets to BLOCKED

        await expect(this.token.connect(this.holder).transfer(this.recipient, initialSupply))
          .to.be.revertedWithCustomError(this.token, 'UserRestricted')
          .withArgs(this.recipient);
      });

      it('allows transfer when restricted user is then unrestricted', async function () {
        await this.token.$_blockUser(this.holder); // Sets to BLOCKED
        await this.token.$_resetUser(this.holder); // Sets back to DEFAULT

        await this.token.connect(this.holder).transfer(this.recipient, initialSupply);
      });
    });

    describe('transfer from', function () {
      let encryptedInput: any;

      beforeEach(async function () {
        const timestamp = (await ethers.provider.getBlock('latest')).timestamp;
        await this.token.connect(this.holder).setOperator(this.approved, timestamp + 1000);

        // Create encrypted input for the transfer amount
        encryptedInput = await fhevm
          .createEncryptedInput(this.token.target, this.approved.address)
          .add64(400)
          .encrypt();
      });

      it('allows transferFrom when sender and recipient are allowed', async function () {
        await this.token
          .connect(this.approved)
          ['confidentialTransferFrom(address,address,bytes32,bytes)'](
            this.holder.address,
            this.recipient.address,
            encryptedInput.handles[0],
            encryptedInput.inputProof,
          );
      });

      it('reverts when sender is BLOCKED', async function () {
        await this.token.$_blockUser(this.holder); // Sets to BLOCKED

        await expect(
          this.token
            .connect(this.approved)
            ['confidentialTransferFrom(address,address,bytes32,bytes)'](
              this.holder.address,
              this.recipient.address,
              encryptedInput.handles[0],
              encryptedInput.inputProof,
            ),
        )
          .to.be.revertedWithCustomError(this.token, 'UserRestricted')
          .withArgs(this.holder);
      });

      it('reverts when recipient is BLOCKED', async function () {
        await this.token.$_blockUser(this.recipient); // Sets to BLOCKED

        await expect(
          this.token
            .connect(this.approved)
            ['confidentialTransferFrom(address,address,bytes32,bytes)'](
              this.holder.address,
              this.recipient.address,
              encryptedInput.handles[0],
              encryptedInput.inputProof,
            ),
        )
          .to.be.revertedWithCustomError(this.token, 'UserRestricted')
          .withArgs(this.recipient);
      });

      it('allows transferFrom when restricted user is then unrestricted', async function () {
        await this.token.$_blockUser(this.holder); // Sets to BLOCKED
        await this.token.$_allowUser(this.holder); // Sets to ALLOWED

        await this.token
          .connect(this.approved)
          ['confidentialTransferFrom(address,address,bytes32,bytes)'](
            this.holder.address,
            this.recipient.address,
            encryptedInput.handles[0],
            encryptedInput.inputProof,
          );
      });
    });

    describe('mint', function () {
      const value = 42n;

      it('allows minting to DEFAULT users', async function () {
        await this.token['$_mint(address,uint64)'](this.recipient, value);
      });

      it('allows minting to ALLOWED users', async function () {
        await this.token.$_allowUser(this.recipient); // Sets to ALLOWED

        await this.token['$_mint(address,uint64)'](this.recipient, value);
      });

      it('reverts when trying to mint to BLOCKED user', async function () {
        await this.token.$_blockUser(this.recipient); // Sets to BLOCKED

        await expect(this.token['$_mint(address,uint64)'](this.recipient, value))
          .to.be.revertedWithCustomError(this.token, 'UserRestricted')
          .withArgs(this.recipient);
      });

      it('allows minting when restricted user is then unrestricted', async function () {
        await this.token.$_blockUser(this.recipient); // Sets to BLOCKED
        await this.token.$_resetUser(this.recipient); // Sets back to DEFAULT

        await this.token['$_mint(address,uint64)'](this.recipient, value);
      });
    });

    describe('burn', function () {
      const value = 42n;

      it('allows burning from DEFAULT users', async function () {
        await this.token['$_burn(address,uint64)'](this.holder, value);
      });

      it('allows burning from ALLOWED users', async function () {
        await this.token.$_allowUser(this.holder); // Sets to ALLOWED

        await this.token['$_burn(address,uint64)'](this.holder, value);
      });

      it('reverts when trying to burn from BLOCKED user', async function () {
        await this.token.$_blockUser(this.holder); // Sets to BLOCKED

        await expect(this.token['$_burn(address,uint64)'](this.holder, value))
          .to.be.revertedWithCustomError(this.token, 'UserRestricted')
          .withArgs(this.holder);
      });

      it('allows burning when restricted user is then unrestricted', async function () {
        await this.token.$_blockUser(this.holder); // Sets to BLOCKED
        await this.token.$_allowUser(this.holder); // Sets to ALLOWED

        await this.token['$_burn(address,uint64)'](this.holder, value);
      });
    });
  });
});
