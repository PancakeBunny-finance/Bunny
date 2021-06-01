/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    version: '0.6.12',
    settings: {
      evmVersion: 'istanbul',
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  }
};
