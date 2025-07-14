import { $VestingWalletConfidentialFactoryMock } from '../../types/contracts-exposed/mocks/finance/VestingWalletConfidentialFactoryMock.sol/$VestingWalletConfidentialFactoryMock';
import { $ConfidentialFungibleTokenMock } from '../../types/contracts-exposed/mocks/token/ConfidentialFungibleTokenMock.sol/$ConfidentialFungibleTokenMock';
import { FhevmType } from '@fhevm/hardhat-plugin';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import { time } from '@nomicfoundation/hardhat-network-helpers';
import { days } from '@nomicfoundation/hardhat-network-helpers/dist/src/helpers/time/duration';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

const name = 'ConfidentialFungibleToken';
const symbol = 'CFT';
const uri = 'https://example.com/metadata';
const startTimestamp = 9876543210;
const duration = 1234;
const cliff = 10;
const amount1 = 101;
const amount2 = 102;

describe('VestingWalletCliffExecutorConfidentialFactory', function () {
  beforeEach(async function () {
    const [holder, recipient, recipient2, operator, executor, ...accounts] = await ethers.getSigners();

    const token = (await ethers.deployContract('$ConfidentialFungibleTokenMock', [
      name,
      symbol,
      uri,
    ])) as any as $ConfidentialFungibleTokenMock;

    const encryptedInput = await fhevm
      .createEncryptedInput(await token.getAddress(), holder.address)
      .add64(1000)
      .encrypt();

    const factory = (await ethers.deployContract(
      '$VestingWalletConfidentialFactoryMock',
    )) as unknown as $VestingWalletConfidentialFactoryMock;

    await token
      .connect(holder)
      ['$_mint(address,bytes32,bytes)'](holder.address, encryptedInput.handles[0], encryptedInput.inputProof);
    const until = (await time.latest()) + days(1);
    await expect(await token.connect(holder).setOperator(await factory.getAddress(), until))
      .to.emit(token, 'OperatorSet')
      .withArgs(holder, await factory.getAddress(), until);

    Object.assign(this, {
      accounts,
      holder,
      recipient,
      recipient2,
      operator,
      executor,
      token,
      factory,
    });
  });

  it('should create vesting wallet with deterministic address', async function () {
    const predictedVestingWalletAddress = await this.factory.predictVestingWalletConfidential(
      this.recipient,
      startTimestamp,
      duration,
      cliff,
      this.executor,
    );
    const vestingWalletAddress = await this.factory.createVestingWalletConfidential.staticCall(
      this.recipient,
      startTimestamp,
      duration,
      cliff,
      this.executor,
    );
    expect(vestingWalletAddress).to.be.equal(predictedVestingWalletAddress);
  });

  it('should create vesting wallet', async function () {
    const vestingWalletAddress = await this.factory.predictVestingWalletConfidential(
      this.recipient,
      startTimestamp,
      duration,
      cliff,
      this.executor,
    );

    await expect(
      await this.factory.createVestingWalletConfidential(
        this.recipient,
        startTimestamp,
        duration,
        cliff,
        this.executor,
      ),
    )
      .to.emit(this.factory, 'VestingWalletConfidentialCreated')
      .withArgs(this.recipient, vestingWalletAddress, startTimestamp, duration, cliff, this.executor);
    const vestingWallet = await ethers.getContractAt('VestingWalletCliffExecutorConfidential', vestingWalletAddress);
    await expect(vestingWallet.owner()).to.eventually.equal(this.recipient);
    await expect(vestingWallet.start()).to.eventually.equal(startTimestamp);
    await expect(vestingWallet.duration()).to.eventually.equal(duration);
    await expect(vestingWallet.cliff()).to.eventually.equal(startTimestamp + cliff);
    await expect(vestingWallet.executor()).to.eventually.equal(this.executor);
  });

  it('should not create vesting wallet twice', async function () {
    await expect(
      await this.factory.createVestingWalletConfidential(
        this.recipient,
        startTimestamp,
        duration,
        cliff,
        this.executor,
      ),
    ).to.emit(this.factory, 'VestingWalletConfidentialCreated');
    await expect(
      this.factory.createVestingWalletConfidential(this.recipient, startTimestamp, duration, cliff, this.executor),
    ).to.be.revertedWithCustomError(this.factory, 'FailedDeployment');
  });

  it('should batch fund vesting wallets', async function () {
    const encryptedInput = await fhevm
      .createEncryptedInput(await this.factory.getAddress(), this.holder.address)
      .add64(amount1)
      .add64(amount2)
      .encrypt();
    const vestingWalletAddress1 = await this.factory.predictVestingWalletConfidential(
      this.recipient,
      startTimestamp,
      duration,
      cliff,
      this.executor,
    );
    const vestingWalletAddress2 = await this.factory.predictVestingWalletConfidential(
      this.recipient2,
      startTimestamp,
      duration,
      cliff,
      this.executor,
    );

    const vestingCreationTx = await this.factory.connect(this.holder).batchFundVestingWalletConfidential(
      this.token.target,
      [
        {
          beneficiary: this.recipient,
          encryptedAmount: encryptedInput.handles[0],
          startTimestamp,
          durationSeconds: duration,
          cliffSeconds: cliff,
        },
        {
          beneficiary: this.recipient2,
          encryptedAmount: encryptedInput.handles[1],
          startTimestamp,
          durationSeconds: duration,
          cliffSeconds: cliff,
        },
      ],
      this.executor,
      encryptedInput.inputProof,
    );

    expect(vestingCreationTx)
      .to.emit(this.factory, 'VestingWalletConfidentialFunded')
      .withArgs(
        vestingWalletAddress1,
        this.recipient,
        this.token.target,
        anyValue,
        startTimestamp,
        duration,
        cliff,
        this.executor,
      )
      .to.emit(this.token, 'ConfidentialTransfer')
      .withArgs(this.holder, vestingWalletAddress2, anyValue)
      .to.emit(this.factory, 'VestingWalletConfidentialFunded')
      .withArgs(
        vestingWalletAddress2,
        this.recipient2,
        this.token.target,
        anyValue,
        startTimestamp,
        duration,
        cliff,
        this.executor,
      )
      .to.emit(this.token, 'ConfidentialTransfer')
      .withArgs(this.holder, vestingWalletAddress2, anyValue);

    const transferEvents = await vestingCreationTx
      .wait()
      .then(tx => tx!.logs.filter(log => log.address === this.token.target));

    const vestingWallet1TransferAmount = transferEvents[0].topics[3];
    const vestingWallet2TransferAmount = transferEvents[1].topics[3];
    expect(
      await fhevm.userDecryptEuint(FhevmType.euint64, vestingWallet1TransferAmount, this.token.target, this.holder),
    ).to.equal(amount1);
    expect(
      await fhevm.userDecryptEuint(FhevmType.euint64, vestingWallet2TransferAmount, this.token.target, this.holder),
    ).to.equal(amount2);
  });

  it('should not batch with invalid cliff', async function () {
    const encryptedInput = await fhevm
      .createEncryptedInput(await this.factory.getAddress(), this.holder.address)
      .add64(amount1)
      .encrypt();

    await expect(
      this.factory.connect(this.holder).batchFundVestingWalletConfidential(
        this.token.target,
        [
          {
            beneficiary: this.recipient,
            encryptedAmount: encryptedInput.handles[0],
            startTimestamp,
            durationSeconds: duration,
            cliffSeconds: duration + 1,
          },
        ],
        this.executor,
        encryptedInput.inputProof,
      ),
    ).to.be.revertedWithCustomError(this.factory, 'VestingWalletCliffConfidentialInvalidCliffDuration');
  });

  it('should not batch with invalid beneficiary', async function () {
    const encryptedInput = await fhevm
      .createEncryptedInput(this.factory.target, this.holder.address)
      .add64(amount1)
      .encrypt();

    await expect(
      this.factory.connect(this.holder).batchFundVestingWalletConfidential(
        this.token.target,
        [
          {
            beneficiary: ethers.ZeroAddress,
            encryptedAmount: encryptedInput.handles[0],
            startTimestamp,
            durationSeconds: duration,
            cliffSeconds: cliff,
          },
        ],
        this.executor,
        encryptedInput.inputProof,
      ),
    ).to.be.revertedWithCustomError(this.factory, 'OwnableInvalidOwner');
  });

  it('should be able to claim tokens after creating wallet', async function () {
    const encryptedInput = await fhevm
      .createEncryptedInput(await this.factory.getAddress(), this.holder.address)
      .add64(amount1)
      .encrypt();

    const vestingWalletParams = [this.recipient, startTimestamp, duration, cliff, this.executor];

    const vestingWallet = await ethers.getContractAt(
      'VestingWalletCliffExecutorConfidential',
      await this.factory.predictVestingWalletConfidential(...vestingWalletParams),
    );

    await this.factory.connect(this.holder).batchFundVestingWalletConfidential(
      this.token.target,
      [
        {
          beneficiary: this.recipient,
          encryptedAmount: encryptedInput.handles[0],
          startTimestamp,
          durationSeconds: duration,
          cliffSeconds: cliff,
        },
      ],
      this.executor,
      encryptedInput.inputProof,
    );

    await this.factory.createVestingWalletConfidential(...vestingWalletParams);

    await time.increaseTo(startTimestamp + duration / 2);
    await vestingWallet.release(this.token);

    await expect(
      fhevm.userDecryptEuint(
        FhevmType.euint64,
        await this.token.confidentialBalanceOf(this.recipient),
        this.token.target,
        this.recipient,
      ),
    ).to.eventually.eq(50);
  });
});
