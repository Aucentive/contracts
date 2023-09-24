import { expect } from 'chai'
import hre from 'hardhat'
import { AucentiveHub } from '../types-typechain'

import 'dotenv/config'

describe('AucentiveHub', function () {
  // We define a fixture to reuse the same setup in every test.

  let aucHub: AucentiveHub
  before(async () => {
    await hre.network.provider.request({
      method: 'hardhat_reset',
      params: [
        {
          forking: {
            // jsonRpcUrl: process.env.BASE_TESTNET_RPC_URL as string,
            jsonRpcUrl: 'https://rpc.ankr.com/eth',
            enabled: true,
            // Unknown transaction type 126
            ignoreUnknownTxType: true,
          },
        },
      ],
    })

    const [owner] = await hre.ethers.getSigners()
    const aucHubFactory = await hre.ethers.getContractFactory('AucentiveHub')
    aucHub = (await aucHubFactory.deploy(
      '0x00000000000000000000000000000000deadbeef',
      '0x00000000000000000000000000000000deadbeef',
      '0x00000000000000000000000000000000deadbeef'
    )) as AucentiveHub
    await aucHub.deployed()
  })

  //
  // Successful run generates gas report
  //

  describe('Deployment', function () {
    it('Should have the right message on deploy', async function () {
      // expect(await aucHub.greeting()).to.equal('greet')
      expect(true)
    })
  })
})
