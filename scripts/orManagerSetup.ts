/* eslint-disable prettier/prettier */
import assert from 'assert';
import { BigNumberish, Wallet, getDefaultProvider } from 'ethers';
import { getMinEnableTime } from '../test/utils.test';
import { ORManager__factory } from '../typechain-types';
import { BridgeLib } from '../typechain-types/contracts/ORManager';
import orManagerConfig from './orManager.config';
import { ethers } from 'hardhat';

export async function managerSetup() {
  const signers = await ethers.getSigners();
  const deployer = new Wallet(
    process.env.DEPLOYER_PRIVATE_KEY || '',
    signers[0].provider,
  );
  console.log('deployer:', deployer.address);

  const envORManagerAddress = process.env['OR_MANAGER_ADDRESS'];
  assert(!!envORManagerAddress, 'Env miss [OR_MANAGER_ADDRESS].');

  const orManager = new ORManager__factory()
    .connect(deployer)
    .attach(envORManagerAddress);

  // registerChains
  const tx1 = await orManager.registerChains(
    getMinEnableTime(),
    orManagerConfig.chains,
  );
  console.log('Hash of registerChains:', tx1.hash);
  await tx1.wait();

  const chainIds: BigNumberish[] = [];
  const tokens: BridgeLib.TokenInfoStruct[] = [];
  for (const chain of orManagerConfig.chains) {
    for (const token of chain.tokens) {
      chainIds.push(chain.id);
      tokens.push(token);
    }
  }

  // updateChainTokens
  if (tokens.length === 0) {
    console.error('Miss tokens');
    return;
  }
  const tx2 = await orManager.updateChainTokens(
    getMinEnableTime(),
    chainIds,
    tokens,
  );
  console.log('Hash of updateChainTokens:', tx2.hash);
  await tx2.wait();

  // updateEbcs
  if (orManagerConfig.ebcs.length === 0) {
    console.error('Miss orManagerConfig.ebcs');
    return;
  }
  const statuses = orManagerConfig.ebcs.map(() => true);
  const tx3 = await orManager.updateEbcs(orManagerConfig.ebcs, statuses);
  console.log('Hash of updateEbcs:', tx3.hash);
  await tx3.wait();

  // updateSubmitter
  if (!orManagerConfig.submitter) {
    console.error('Miss orManagerConfig.submitter');
    return;
  }
  const tx4 = await orManager.updateSubmitter(
    getMinEnableTime(),
    orManagerConfig.submitter,
  );
  console.log('Hash of updateSubmitter:', tx4.hash);
  await tx4.wait();
}

async function main() {
  await managerSetup();
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
