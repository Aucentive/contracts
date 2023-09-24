import '@nomiclabs/hardhat-ethers'
import '@nomiclabs/hardhat-etherscan'
import '@typechain/hardhat'
import 'dotenv/config'
import 'hardhat-contract-sizer'
import 'hardhat-deploy'
import 'hardhat-gas-reporter'
import 'solidity-coverage'
import '@openzeppelin/hardhat-upgrades'
import { HardhatUserConfig } from 'hardhat/config'

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more
const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: '0.8.0',
        settings: {
          optimizer: {
            enabled: true,
            runs: 100,
          },
        },
      },
      {
        version: '0.7.0',
        settings: {
          optimizer: {
            enabled: true,
            runs: 100,
          },
        },
      },
      {
        version: '0.6.12',
        settings: {
          optimizer: {
            enabled: true,
            runs: 100,
          },
        },
      },
      {
        version: '0.4.24',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  networks: {
    hardhat: {
      accounts: { mnemonic: 'test test test test test test test test test test test junk' },
      forking: {
        // url: process.env.BASE_TESTNET_RPC_URL as string,
        url: 'https://rpc.ankr.com/eth',
        // blockNumber: parseInt('17230520'),
        enabled: true,
      },
      chainId: 84531,
      // live: false,
      // gas: 10_000_000,
      // gasPrice: 103112366939,
    },
    mainnet: {
      accounts: [process.env.BASE_MAINNET_PRIVATE_KEY as string],
      url: process.env.BASE_MAINNET_RPC_URL as string,
      gas: 'auto',
      live: true,
    },
    goerli: {
      accounts: [process.env.BASE_TESTNET_PRIVATE_KEY as string],
      url: process.env.BASE_TESTNET_RPC_URL as string,
      gas: 'auto',
      live: true,
    },
  },
  mocha: {
    timeout: 60 * 30 * 1000,
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  namedAccounts: {
    deployer: 0,
  },
  gasReporter: {
    // enabled: process.env.REPORT_GAS ? true : false,
    enabled: true,
  },
}

export default config
