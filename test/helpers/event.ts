import { EventLog } from 'ethers';
import { ContractTransactionResponse } from 'ethers';
import { ethers } from 'ethers';

export async function callAndGetResult(txPromise: Promise<ContractTransactionResponse>, eventName: string) {
  const receipt = await txPromise.then(tx => tx.wait());
  const logs = receipt?.logs.filter(log => log.address == receipt.to && log.topics[0] == ethers.id(eventName));
  return (logs![0] as EventLog).args;
}
