import { expect } from "chai";
import hre, { ethers } from "hardhat";

import { awaitAllDecryptionResults, initGateway } from "../../_template/asyncDecrypt";
import { createInstance } from "../../_template/instance";
import { reencryptEuint64 } from "../../_template/reencrypt";
import { impersonate } from "../../helpers/accounts";

const name = "ConfidentialFungibleTokenVotes";
const symbol = "CFT";
const uri = "https://example.com/metadata";

describe("ConfidentialFungibleTokenVotes", function () {
  beforeEach(async function () {
    const accounts = await ethers.getSigners();
    const [holder, recipient, operator] = accounts;

    const token = await ethers.deployContract("$ConfidentialFungibleTokenVotes", [name, symbol, uri]);

    this.fhevm = await createInstance();
    this.accounts = accounts.slice(3);
    this.holder = holder;
    this.recipient = recipient;
    this.token = token;
    this.operator = operator;
  });

  it("test temp", async function () {
    console.log(this.token);
  });
});
