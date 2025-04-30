import { setCode } from "@nomicfoundation/hardhat-network-helpers";
import { ethers } from "ethers";
import { task } from "hardhat/config";

import { impersonate } from "../test/helpers/accounts";

export const ACL_ADDRESS = "0xfee8407e2f5e3ee68ad77cae98c434e637f516e5";
export const FHEPAYMENT_ADDRESS = "0xfb03be574d14c256d56f09a198b586bdfc0a9de2";
export const GATEWAYCONTRACT_ADDRESS = "0x33347831500f1e73f0cccbb95c9f86b94d7b1123";
export const INPUTVERIFIER_ADDRESS = "0x3a2DA6f1daE9eF988B48d9CF27523FA31a8eBE50";
export const KMSVERIFIER_ADDRESS = "0x9d6891a6240d6130c54ae243d8005063d05fe14b";
export const TFHEEXECUTOR_ADDRESS = "0x687408ab54661ba0b4aef3a44156c616c6955e07";
export const KMSSIGNER_PK = "0x388b7680e4e1afa06efbfd45cdd1fe39f3c6af381df6555a19661f283b97de91";

task("test", async (_taskArgs, hre, runSuper) => {
  if (hre.network.name === "hardhat") {
    const zeroSigner = await impersonate(hre, "0x0000000000000000000000000000000000000000");
    const oneSigner = await impersonate(hre, "0x0000000000000000000000000000000000000001");
    const kmsSigner = new ethers.Wallet(KMSSIGNER_PK);

    const [, , gateway, input, kms] = await Promise.all(
      Object.entries({
        [ACL_ADDRESS]: "fhevm-core-contracts/artifacts/contracts/ACL.sol/ACL.json",
        [FHEPAYMENT_ADDRESS]: "fhevm-core-contracts/artifacts/contracts/FHEPayment.sol/FHEPayment.json",
        [GATEWAYCONTRACT_ADDRESS]: "fhevm-core-contracts/artifacts/gateway/GatewayContract.sol/GatewayContract.json",
        [INPUTVERIFIER_ADDRESS]:
          "fhevm-core-contracts/artifacts/contracts/InputVerifier.coprocessor.sol/InputVerifier.json",
        [KMSVERIFIER_ADDRESS]: "fhevm-core-contracts/artifacts/contracts/KMSVerifier.sol/KMSVerifier.json",
        [TFHEEXECUTOR_ADDRESS]:
          "fhevm-core-contracts/artifacts/contracts/TFHEExecutorWithEvents.sol/TFHEExecutorWithEvents.json",
      }).map(([address, path]) =>
        import(path).then(({ abi, deployedBytecode }) =>
          setCode(address, deployedBytecode).then(() => hre.ethers.getContractAt(abi, address)),
        ),
      ),
    );

    await kms.connect(zeroSigner).initialize(oneSigner.address);
    await Promise.all([
      kms.connect(oneSigner).addSigner(kmsSigner.address),
      input.connect(zeroSigner).initialize(oneSigner.address),
      gateway.connect(zeroSigner).addRelayer(zeroSigner.address),
    ]);
  }
  await runSuper();
});
