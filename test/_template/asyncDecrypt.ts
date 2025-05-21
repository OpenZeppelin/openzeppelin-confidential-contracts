import { Wallet, ZeroAddress } from "ethers";
import gatewayArtifact from "fhevm-core-contracts/artifacts/gateway/GatewayContract.sol/GatewayContract.json";
import { ethers, network } from "hardhat";

import { impersonate } from "../helpers/accounts";
import { ACL_ADDRESS, GATEWAYCONTRACT_ADDRESS, KMSVERIFIER_ADDRESS, PRIVATE_KEY_KMS_SIGNER } from "./constants";
import { awaitCoprocessor, getClearText } from "./coprocessorUtils";
import { waitNBlocks } from "./utils";

const networkName = network.name;
const aclAdd = ACL_ADDRESS;

const CiphertextType = {
  0: "bool",
  1: "uint8", // corresponding to euint4
  2: "uint8", // corresponding to euint8
  3: "uint16",
  4: "uint32",
  5: "uint64",
  6: "uint128",
  7: "address",
  8: "uint256",
  9: "bytes",
  10: "bytes",
  11: "bytes",
};

const currentTime = (): string => {
  const now = new Date();
  return now.toLocaleTimeString("en-US", { hour12: true, hour: "numeric", minute: "numeric", second: "numeric" });
};

const argEvents =
  "(uint256 indexed requestID, uint256[] cts, address contractCaller, bytes4 callbackSelector, uint256 msgValue, uint256 maxTimestamp, bool passSignaturesToCaller)";
const ifaceEventDecryption = new ethers.Interface(["event EventDecryption" + argEvents]);

const argEvents2 = "(uint256 indexed requestID, bool success, bytes result)";
const ifaceResultCallback = new ethers.Interface(["event ResultCallback" + argEvents2]);

let gateway;
let firstBlockListening: number;
let lastBlockSnapshotForDecrypt: number;

export const initGateway = async (): Promise<void> => {
  firstBlockListening = await ethers.provider.getBlockNumber();
  if (networkName === "hardhat" && hre.__SOLIDITY_COVERAGE_RUNNING !== true) {
    // evm_snapshot is not supported in coverage mode
    await ethers.provider.send("set_lastBlockSnapshotForDecrypt", [firstBlockListening]);
  }
  // this function will emit logs for every request and fulfillment of a decryption
  gateway = await ethers.getContractAt(gatewayArtifact.abi, GATEWAYCONTRACT_ADDRESS);
  gateway.on(
    "EventDecryption",
    async (requestID, cts, contractCaller, callbackSelector, msgValue, maxTimestamp, eventData) => {
      const blockNumber = eventData.log.blockNumber;
      console.log(`${await currentTime()} - Requested decrypt on block ${blockNumber} (requestID ${requestID})`);
    },
  );
  gateway.on("ResultCallback", async (requestID, success, result, eventData) => {
    const blockNumber = eventData.log.blockNumber;
    console.log(`${await currentTime()} - Fulfilled decrypt on block ${blockNumber} (requestID ${requestID})`);
  });
};

export const awaitAllDecryptionResults = async (): Promise<void> => {
  gateway = await ethers.getContractAt(gatewayArtifact.abi, GATEWAYCONTRACT_ADDRESS);
  const provider = ethers.provider;
  if (networkName === "hardhat" && hre.__SOLIDITY_COVERAGE_RUNNING !== true) {
    // evm_snapshot is not supported in coverage mode
    lastBlockSnapshotForDecrypt = await provider.send("get_lastBlockSnapshotForDecrypt");
    if (lastBlockSnapshotForDecrypt < firstBlockListening) {
      firstBlockListening = lastBlockSnapshotForDecrypt + 1;
    }
  }
  await fulfillAllPastRequestsIds(networkName === "hardhat");
  firstBlockListening = (await ethers.provider.getBlockNumber()) + 1;
  if (networkName === "hardhat" && hre.__SOLIDITY_COVERAGE_RUNNING !== true) {
    // evm_snapshot is not supported in coverage mode
    await provider.send("set_lastBlockSnapshotForDecrypt", [firstBlockListening]);
  }
};

const getAlreadyFulfilledDecryptions = async (): Promise<[bigint]> => {
  let results = [];
  const eventDecryptionResult = await gateway.filters.ResultCallback().getTopicFilter();
  const filterDecryptionResult = {
    address: GATEWAYCONTRACT_ADDRESS,
    fromBlock: firstBlockListening,
    toBlock: "latest",
    topics: eventDecryptionResult,
  };
  const pastResults = await ethers.provider.getLogs(filterDecryptionResult);
  results = results.concat(pastResults.map((result) => ifaceResultCallback.parseLog(result).args[0]));
  return results;
};

const allTrue = (arr: boolean[], fn = Boolean) => arr.every(fn);

const fulfillAllPastRequestsIds = async (mocked: boolean) => {
  const eventDecryption = await gateway.filters.EventDecryption().getTopicFilter();
  const results = await getAlreadyFulfilledDecryptions();
  const filterDecryption = {
    address: GATEWAYCONTRACT_ADDRESS,
    fromBlock: firstBlockListening,
    toBlock: "latest",
    topics: eventDecryption,
  };
  const pastRequests = await ethers.provider.getLogs(filterDecryption);
  for (const request of pastRequests) {
    const event = ifaceEventDecryption.parseLog(request);
    const requestID = event.args[0];
    const handles = event.args[1];
    const typesList = handles.map((handle) => parseInt(handle.toString(16).slice(-4, -2), 16));
    const msgValue = event.args[4];

    if (!results.includes(requestID)) {
      // if request is not already fulfilled
      if (mocked) {
        // in mocked mode, we trigger the decryption fulfillment manually
        await awaitCoprocessor();
        // first check that all handles are allowed for decryption
        const { abi: aclAbi } = await import("fhevm-core-contracts/artifacts/contracts/ACL.sol/ACL.json");
        const acl = await ethers.getContractAt(aclAbi, ACL_ADDRESS);
        const isAllowedForDec = await Promise.all(
          handles.map(async (handle: bigint) => acl.isAllowedForDecryption(handle)),
        );
        if (!allTrue(isAllowedForDec)) {
          throw new Error("Some handle is not authorized for decryption");
        }
        const types = typesList.map((num) => CiphertextType[num]);
        const values = await Promise.all(handles.map(async (handle) => BigInt(await getClearText(handle))));
        const valuesFormatted = values.map((value, index) =>
          types[index] === "address" ? "0x" + value.toString(16).padStart(40, "0") : value,
        );
        const valuesFormatted2 = valuesFormatted.map((value, index) =>
          typesList[index] === 9 ? "0x" + value.toString(16).padStart(128, "0") : value,
        );
        const valuesFormatted3 = valuesFormatted2.map((value, index) =>
          typesList[index] === 10 ? "0x" + value.toString(16).padStart(256, "0") : value,
        );
        const valuesFormatted4 = valuesFormatted3.map((value, index) =>
          typesList[index] === 11 ? "0x" + value.toString(16).padStart(512, "0") : value,
        );

        const abiCoder = new ethers.AbiCoder();

        const encodedData = abiCoder.encode(["uint256", ...types], [31, ...valuesFormatted4]); // 31 is just a dummy uint256 requestID to get correct abi encoding for the remaining arguments (i.e everything except the requestID)
        const calldata = "0x" + encodedData.slice(66); // we just pop the dummy requestID to get the correct value to pass for `decryptedCts`

        const numSigners = 1; // for the moment mocked mode only uses 1 signer
        const decryptResultsEIP712signatures = await computeDecryptSignatures(handles, calldata, numSigners);
        const relayer = await impersonate(hre, ZeroAddress, ethers.parseEther("100"));
        await gateway
          .connect(relayer)
          .fulfillRequest(requestID, calldata, decryptResultsEIP712signatures, { value: msgValue });
      } else {
        // in non-mocked mode we must wait until the gateway service relayer submits the decryption fulfillment tx
        await waitNBlocks(1);
        await fulfillAllPastRequestsIds(mocked);
      }
    }
  }
};

async function computeDecryptSignatures(
  handlesList: bigint[],
  decryptedResult: string,
  numSigners: number,
): Promise<string[]> {
  const signatures: string[] = [];

  for (let idx = 0; idx < numSigners; idx++) {
    const privKeySigner = PRIVATE_KEY_KMS_SIGNER;
    if (privKeySigner) {
      const kmsSigner = new ethers.Wallet(privKeySigner).connect(ethers.provider);
      const signature = await kmsSign(handlesList, decryptedResult, kmsSigner);
      signatures.push(signature);
    } else {
      throw new Error(`Private key for signer ${idx} not found in environment variables`);
    }
  }
  return signatures;
}

async function kmsSign(handlesList: bigint[], decryptedResult: string, kmsSigner: Wallet) {
  const kmsAdd = KMSVERIFIER_ADDRESS;
  const chainId = (await ethers.provider.getNetwork()).chainId;

  const domain = {
    name: "KMSVerifier",
    version: "1",
    chainId: chainId,
    verifyingContract: kmsAdd,
  };

  const types = {
    DecryptionResult: [
      {
        name: "aclAddress",
        type: "address",
      },
      {
        name: "handlesList",
        type: "uint256[]",
      },
      {
        name: "decryptedResult",
        type: "bytes",
      },
    ],
  };
  const message = {
    aclAddress: aclAdd,
    handlesList: handlesList,
    decryptedResult: decryptedResult,
  };

  const signature = await kmsSigner.signTypedData(domain, types, message);
  const sigRSV = ethers.Signature.from(signature);
  const v = 27 + sigRSV.yParity;
  const r = sigRSV.r;
  const s = sigRSV.s;

  const result = r + s.substring(2) + v.toString(16);
  return result;
}
