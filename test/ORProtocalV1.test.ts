/* eslint-disable @typescript-eslint/ban-ts-comment */
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { ethers } from 'hardhat';
import { loadOrDeployContract } from '../scripts/utils';
// import { BigNumber } from "bignumber.js";
import _ from 'lodash';
import { ORManager, ORProtocalV1 } from '../typechain-types';
const VeiftFromCodeList = require('./fromTxCode.mock.json');
const VeiftToCodeList = require('./toTxCode.mock.json');
import {
  DataInit,
  getORProtocalV1Contract,
  getORSPVContract,
  getSPVProof,
} from './utils.test';
let ebc: ORProtocalV1;
let ebcOwner: SignerWithAddress;
let managerContractAddress: string;
describe('ORProtocalV1.test.ts', () => {
  async function createEbcInfo() {
    [ebcOwner] = await ethers.getSigners();
    ebc = await getORProtocalV1Contract();
    const manager = await loadOrDeployContract<ORManager>('ORManager');
    managerContractAddress = manager.address;
  }

  before(createEbcInfo);

  it('Update EBC and SPV factory', async () => {
    const spvContract = await getORSPVContract();
    !expect(managerContractAddress).not.empty;
    !expect(spvContract.address).not.empty;
    const factoryContract = await ethers.getContractAt(
      'ORManager',
      managerContractAddress,
    );
    await factoryContract.addEBC(ebc.address);
    await factoryContract.setSPV(spvContract.address).then(async (tx) => {
      await tx.wait();
      expect(await factoryContract.getSPV()).equal(spvContract.address);
    });
    expect((await factoryContract.getEbcIds())[0]).equal(ebc.address);
  });
  it('getFromTxChainId 1', async () => {
    const result = await ebc.getTxValueToChainId('272970000009002002');
    expect(result).eq(9002);
  });
  it('getFromTxChainId', async () => {
    const tx = DataInit.userTxList[0];
    const result = await ebc.getFromTxChainId(tx);
    expect(result).eq(9022);
  });
  it('getToTxNonceId', async () => {
    const tx = DataInit.makerTxList[0];
    const result = await ebc.getToTxNonceId(tx);
    expect(result).eq(DataInit.userTxList[0].nonce);
  });

  it('getResponseAmount', async function () {
    this.timeout(1000 * 60 * 30);
    const txList = DataInit.userTxList;
    const result = {
      success: 0,
      fail: 0,
    };
    const tx = _.clone(txList[0]);
    const list = VeiftFromCodeList.filter(
      (row: { chainId: number; memo: number; symbol: string }) =>
        row.chainId == 1 && row.memo == 2 && row.symbol == 'ETH',
    );
    console.log(list.length, '=====list');
    for (const row of list) {
      break;
      tx.value = row.value.replace('9002', '0000');
      tx.nonce = row.nonce;
      console.log(row, '===');
      const amount = await ebc.getResponseAmountTest(
        tx,
        150000000000000,
        1200000000000000,
      );
      if (row.expectValue == amount) {
        result.success++;
      } else {
        result.fail++;
      }
      console.log(
        'calc:',
        amount.toString(),
        ',expectValue:',
        row.expectValue,
        'result:',
        row.expectValue == amount,
      );
    }
    console.log(result, '===result');
    // const fromAmount = new BigNumber('0.010100000000009022');
    // const data2 = fromAmount.minus(ethers.BigNumber.from(('100000000000000000')));
    // console.log(data2.toString(), '=========');
    // const data3 = data2.mul(ethers.BigNumber.from())
    // "c1TradingFee": 0.0001,
    // "c2TradingFee": 0.0001,
    // "c1GasFee": 1,
    // "c2GasFee": 1,
    // const result = await ebc.config();
    // console.log(result);
  });

  // it('Get Safety Code From TxList', async function () {
  //   this.timeout(1000 * 60 * 30);
  //   const unmatched = [];
  //   const list: any[] = _.take(_.shuffle(VeiftFromCodeList), 100);
  //   for (const tx of list) {
  //     try {
  //       const code = await ebc.getValueSecuirtyCode(
  //         tx.chainId,
  //         ethers.BigNumber.from(tx.value),
  //       );
  //       const toChainId = Number(code) % 9000;
  //       if (toChainId != tx.memo) {
  //         tx.result = toChainId;
  //         tx.response = code;
  //         unmatched.push(tx);
  //       }
  //     } catch (error) {
  //       console.log(`error:`, error, tx);
  //     }
  //   }
  //   console.log('Match Result', unmatched);
  //   console.log(
  //     `Response  ${unmatched.length}/${list.length - unmatched.length}/${list.length
  //     }`,
  //   );
  //   // expect(result).equal(148);
  // });
  // it('Get Safety Code To TxList', async function () {
  //   this.timeout(1000 * 60 * 30);
  //   const unmatched = [];
  //   const list: any[] = take(shuffle(VeiftToCodeList), 100);
  //   for (const tx of list) {
  //     try {
  //       const code = await ebc.getValueSecuirtyCode(
  //         tx.chainId,
  //         ethers.BigNumber.from(tx.value),
  //       );
  //       const toChainId = Number(code) % 9000;
  //       if (toChainId != tx.memo) {
  //         tx.result = toChainId;
  //         tx.response = code;
  //         unmatched.push(tx);
  //       }
  //     } catch (error) {
  //       console.log(`error:`, error, tx);
  //     }
  //   }
  //   console.log(
  //     `Math Result  ${unmatched.length}/${list.length - unmatched.length}/${list.length
  //     }`,
  //   );
  //   // expect(result).equal(148);
  // });

  it('setAndGetChallengePledgeAmountCoefficient', async () => {
    const value = ethers.utils.parseEther('0.05');
    await ebc.connect(ebcOwner).setChallengePledgedAmount(value);
    const result = await ebc.config();
    expect(result.challengePledgedAmount).eq(value);
  });
  it('setAndGetDepositAmountCoefficient', async () => {
    const value = 1000;
    await ebc.connect(ebcOwner).setPledgeAmountSafeRate(value);
    // const result = await ebc.getPledgeAmountSafeRate();
    const batchLimit = ethers.BigNumber.from(100),
      maxPrice = ethers.BigNumber.from('100000000000000000');
    const pledgeAmount = await ebc.getPledgeAmount(batchLimit, maxPrice);
    expect(pledgeAmount.baseValue.add(pledgeAmount.additiveValue)).eq(
      ethers.BigNumber.from('11000000000000000000'),
    );
  });
  it('setAndGetETHPunishCoefficient', async () => {
    const value = 100;
    await ebc
      .connect(ebcOwner)
      .setMainCoinPunishRate(value)
      .then(async (tx) => {
        await tx.wait();
        const result = await ebc.config();
        expect(result.mainCoinPunishRate).eq(value);
      });
  });
  it('setAndGetTokenPunishCoefficient', async () => {
    const value = 100;
    await ebc
      .connect(ebcOwner)
      .setTokenPunishRate(value)
      .then(async (tx) => {
        await tx.wait();
        const result = await ebc.config();
        expect(result.tokenPunishRate).eq(value);
      });
  });
  // it('getETHPunish', async () => {
  //   const value = USER_TX_LIST[0].value;
  //   const response = await ebc.calculateCompensation(
  //     USER_TX_LIST[0].token,
  //     value,
  //   );
  //   expect(response.baseValue.add(response.additiveValue)).gt(
  //     ethers.BigNumber.from(value),
  //   );
  // });
  // it('getTokenPunish', async () => {
  //   const value = USER_TX_LIST[0].value;
  //   const response = await ebc.calculateCompensation(
  //     '0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0',
  //     value,
  //   );
  //   expect(response.baseValue.add(response.additiveValue)).gt(
  //     ethers.BigNumber.from(value),
  //   );
  // });

  it('getRespnseHash', async () => {
    // const realResponse1 = await ebc.getResponseHash(
    //   DataInit.userTxList[0],
    //   true,
    // );
    // const realResponse2 = await ebc.getResponseHash(
    //   DataInit.userTxList[2],
    //   false,
    // );
    // expect(realResponse1).equals(realResponse2);
  });
});

describe('SPV Veify', () => {
  it('update L2RootHash And NodeRootHash', async () => {
    const UserTreeHash =
      '0xf064e5136311e29602148eaeae16ae35ac3387d3cf3bee30fd907a342c08f698';
    const NodeRootHash =
      '0x9c807909d4dae064933061088fbaf31310913320c2602a84cdbf657f8b82292e';
    const spv = await getORSPVContract();
    const updateL2RootHash = await spv.updateUserTreeHash(UserTreeHash);
    await updateL2RootHash.wait();
    const updateNodeRootHash = await spv.updateNodeTreeHash(NodeRootHash);
    await updateNodeRootHash.wait();
    const nowUserTreeHash = await spv.userTreeRootHash();
    const nowNodeRootHash = await spv.nodeDataRootHash();
    expect(nowUserTreeHash).eq(UserTreeHash);
    expect(nowNodeRootHash).eq(NodeRootHash);
  });
  it('startValidate From', async () => {
    const result = await getSPVProof(
      '9005',
      '0xafee4ad1a2d0f54fdfde4a5f259c9d035b0ed39a8f615477f59c021ac2a274ad',
    );
    expect(result).not.empty;

    if (result) {
      const spv = await getORSPVContract();
      const validResult: any = await spv.startValidate(result);
      expect(validResult.txHash).eq(
        '0xafee4ad1a2d0f54fdfde4a5f259c9d035b0ed39a8f615477f59c021ac2a274ad',
      );
    }
  });

  it('startValidate To', async () => {
    const result = await getSPVProof(
      '9022',
      '0x41080ea8df1841a67745f3d9a5315f8242c003ae3a1f0f8f610f0608008efdb5',
      '0x74c88fb66e8a580dfffadbbbbad48408e51067dec084b2cb6148f0ed558c3c63',
    );
    expect(result).not.empty;
    if (result) {
      const spv = await getORSPVContract();
      const validResult: any = await spv.startValidate(result);
      expect(validResult.txHash).eq(
        '0x74c88fb66e8a580dfffadbbbbad48408e51067dec084b2cb6148f0ed558c3c63',
      );
    }
  });
});
