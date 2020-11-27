const { mnemonic, addressIndex } = require('./secrets.json')
const HDWalletProvider = require('@truffle/hdwallet-provider')

module.exports = {
  networks: {
    development: {
      protocol: 'http',
      host: 'localhost',
      port: 8545,
      gas: 5000000,
      gasPrice: 5e9,
      networkId: '*',
    },
    bsc: {
      provider: () => new HDWalletProvider(mnemonic, 'https://bsc-dataseed.binance.org', addressIndex),
      networkId: 56,
      gas: 6000000,
      gasPrice: 20e9
    }
  },
};