/* eslint-disable prettier/prettier */
import assert from 'assert';
import { BigNumberish, Wallet, getDefaultProvider } from 'ethers';
import { getMinEnableTime } from '../test/utils.test';
import { ORManager__factory } from '../typechain-types';
import { BridgeLib } from '../typechain-types/contracts/ORManager';
// import orManagerConfig from './orManager.config';
import { ethers } from 'hardhat';
import { deploymentChainInfoArray, tokenDefault } from './orManager.config';

// TODO: It will be merged into `orManagerSetup.ts` later, and initial configuration or new network will be distinguished based on parameters.
export async function managerSetupScroll() {
  const signers = await ethers.getSigners();
  const deployer = new Wallet(
    process.env.DEPLOYER_PRIVATE_KEY || '',
    signers[0].provider,
  );
  console.log('deployer:', deployer.address);

  const envORManagerAddress = process.env['OR_MANAGER_ADDRESS'];
  assert(!!envORManagerAddress, 'Env miss [OR_MANAGER_ADDRESS].');

  // Only scroll network
  const chains = deploymentChainInfoArray.filter((c) => c.id + '' == '534352');
  if (chains.length === 0) {
    console.error('Miss chains');
    return;
  }

  const orManager = new ORManager__factory()
    .connect(deployer)
    .attach(envORManagerAddress);

  // registerChains
  const tx1 = await orManager.registerChains(
    getMinEnableTime(),
    chains,
  );
  console.log('Hash of registerChains:', tx1.hash);
  await tx1.wait();

  const chainIds: BigNumberish[] = [534352];
  const tokens: BridgeLib.TokenInfoStruct[] = [tokenDefault];

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
}

async function main() {
  await managerSetupScroll();
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
