const { interfaceId } = require('@openzeppelin/contracts/test/helpers/methods');
const { mapValues } = require('@openzeppelin/contracts/test/helpers/iterate');

export const SIGNATURES = {
  ERC165: ['supportsInterface(bytes4)'],
  ERC1363Receiver: ['onTransferReceived(address,address,uint256,bytes)'],
  ERC7984: [
    'confidentialBalanceOf(address)',
    'confidentialTotalSupply()',
    'confidentialTransfer(address,bytes32,bytes)',
    'confidentialTransfer(address,bytes32)',
    'confidentialTransferAndCall(address,bytes32,bytes,bytes)',
    'confidentialTransferAndCall(address,bytes32,bytes)',
    'confidentialTransferFrom(address,address,bytes32,bytes)',
    'confidentialTransferFrom(address,address,bytes32)',
    'confidentialTransferFromAndCall(address,address,bytes32,bytes,bytes)',
    'confidentialTransferFromAndCall(address,address,bytes32,bytes)',
    'contractURI()',
    'decimals()',
    'isOperator(address,address)',
    'name()',
    'setOperator(address,uint48)',
    'symbol()',
  ],
  ERC7984ERC20Wrapper: [
    'underlying()',
    'unwrap(address,address,bytes32)',
    'unwrap(address,address,bytes32,bytes)',
    'wrap(address,uint256)',
  ],
  ERC7984RWA: [
    'blockUser(address)',
    'confidentialAvailable(address)',
    'confidentialBurn(address,bytes32,bytes)',
    'confidentialBurn(address,bytes32)',
    'confidentialFrozen(address)',
    'confidentialMint(address,bytes32,bytes)',
    'confidentialMint(address,bytes32)',
    'forceConfidentialTransferFrom(address,address,bytes32,bytes)',
    'forceConfidentialTransferFrom(address,address,bytes32)',
    'isUserAllowed(address)',
    'pause()',
    'paused()',
    'setConfidentialFrozen(address,bytes32,bytes)',
    'setConfidentialFrozen(address,bytes32)',
    'unblockUser(address)',
    'unpause()',
  ],
};

export const INTERFACE_IDS = mapValues(SIGNATURES, interfaceId);

export const INVALID_ID = '0xffffffff';
