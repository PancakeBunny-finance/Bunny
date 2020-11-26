const {
    FARMER0,
    DEPLOYER, KEEPER, FARMERS
} = require('./test/constants')

const unlocked_accounts = [FARMER0, DEPLOYER, KEEPER, ...FARMERS]

module.exports = {
    accounts: {
        amount: 10, // Number of unlocked accounts
        ether: 10000, // Initial balance of unlocked accounts (in ether)
    },
    // setupProvider: (baseProvider) => {
    //     const { GSNDevProvider } = require('@openzeppelin/gsn-provider');
    //     const { accounts } = require('@openzeppelin/test-environment');
    //
    //     return new GSNDevProvider(baseProvider, {
    //         txfee: 1,
    //         useGSN: false,
    //         ownerAddress: accounts[8],
    //         relayerAddress: accounts[9],
    //     });
    // },
    node: { // Options passed directly to Ganache client
        fork: 'https://bsc-dataseed.binance.org/',
        unlocked_accounts: unlocked_accounts,
        gasLimit: 12000000
    }
};