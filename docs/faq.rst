************
FAQ
************

What is Pancake Bunny?
================================================

PancakeBunny is a new and rapidly growing DeFi yield aggregator that is used for PancakeSwap. The PancakeBunny protocol empowers farmers to leverage their yield-seeking tendencies to optimize yield compounding strategy on BSC. We are providing strategies for the various needs of farmers from the highest yield seekers to the risk reward optimizing smart investors.

What is the Reason for launching Pancake Bunny?
================================================

We wanted to create a platform that automatically compounds yields for all individuals, no matter how small your stake may be. Our goal is to expand the DeFi ecosystem, specifically on the Binance Smart Chain, while providing users with various strategies to maximize returns while minimizing risk.

How do Bunny Farms Work?
================================================

Currently, the majority of our farms are those that exist on Pancake Swap. Essentially the farms on our platform get permission from individuals via smart contracts to automatically compound and reinvest yields on behalf of individuals.

Can’t I just compound by myself?
================================================

Compounding yourself on PancakeSwap is a very tedious process and it is often hard to know the optimal frequency and timing of when to compound and reinvest your yields. Bunny does all of this for you plus saves you gas fees.

What is the BUNNY Token?
================================================

BUNNY Token is our native governance token. BUNNY holders govern our ecosystem and receive the majority of farm performance fee profits. Holding/Staking BUNNY is not only beneficial for individual profits, but also ensures the Bunny Ecosystem runs smoothly.

Which Bunny Farm do I pick?
================================================

Every Farm requires a different LP Token. Furthermore the different Farms represent different risk tolerances for Bunny users. A high APY usually means more volatility in the underlying token price. For example, BUSD-BNB has a much lower compounded APY than CAKE-BNB, since BUSD is a stable coin which is pegged to the dollar and does not experience volatility.

What are the risks of Farming on Bunny?
================================================

Systematic Risk

The Systematic Risk would be the decrease of monetary value of assets deposited, be in BNB, CAKE, etc. For example BNB could be $30 when you deposit and $25 when you withdraw

Idiosyncratic Risk

The Idiosyncratic Risk would be risks associated with our actual project. Although our code has been audited by Haechi Labs, there are always risks that projects will fall victim to malicious hackers. That being said, our Bunny developers account for the security risks of smart contracts and only will interact with contracts that meet the security threshold.

How to Determine Daily % Gains?
================================================

Because the APY is constantly changing on Pancake Swap, the Compounded APY on the Bunny Platform is constantly changing. Furthermore, because this APY is calculated via compounded (exponential growth), it cannot be calculated in a linear manner (i.e. APY/365) So long as you hold your tokens in our farms for an extended period of time, your assets will continue to grow exponentially.

Where does CAKE or LP come from in the rewards?
================================================

CAKE or the LP tokens are all used from Pancakeswap, we automatically compound yields via Pancakeswap.

Where does BUNNY come from?
================================================

BUNNY is minted via the project's smart contracts.

When the user executes a Claim on their profits in a given Pool, they receive 70% of the profit's value in the respective auto-compounded farm token, and receive 30% of the profit's value in BUNNY.

This 30% worth of profit is calculated in $ equivalent of BNB, and for every 1 BNB the user gets 15 BUNNY.


Where does Swap % come from?
================================================

The swap percentage is an estimation based on the swap fee that liquidity providers receive every time someone swaps that pair. These rewards go to the LP token itself, causing its value to increase, which in turn causes your share to increase. The displayed percentage rate is obtained via the PancakeSwap API.

Which rewards get compounded?
================================================

Currently, all the farms get compounded except for the BUNNY Staking farm and the BUNNY/BNB farm.

When the user executes a Claim on their profits in a given Pool, they receive 70% of the profit's value in the respective auto-compounded farm token, and receive 30% of the profit's value in BUNNY.

What is the Fee Structure?
================================================

Withdrawal Fee

There is a 0.5% withdrawal fee from Farms only if a Withdrawal happens within 72 hours of deposit. This fee exists to maintain the smooth flow of the ecosystem and to prevent possible exploitation from individuals acting under bad faith. For example if there was no 0.5% withdrawal fee within the 72 hours, someone could keep depositing right before the compounding takes place and withdraw right after and still reap the same benefits and continuous long-term holders.

Performance Fee

When you choose to Claim profits from a pool, a 30% performance fee is collected to reward BUNNY stake holders. In return, all pools are rewarded with BUNNY tokens. For every 1 BNB in fees collected, 15 BUNNY is rewarded.

Can I make a partial withdrawal?
================================================

Yes. On the Pool screen:

1. Next to the "Deposit", tap or click 'Withdraw"

2. Enter in the amount of Tokens you wish to withdraw or select "Max" to select all of your Tokens in the pool.

3. Tap the "Withdraw" button at the bottom

Why are the transaction fees so high?
================================================

The GAS LIMIT is the maximum amount of gas that can be spent on a transaction. In some pools the GAS LIMIT is set higher than others even on claim actions. This is due to the complexity of our contracts and to ensure the transactions do not fail in case of BSC instability or high transactions load.

Take note that the gas spent will be usually half of the gas limit set. You can always check the transaction on bscscan.com to see more details.

Why does my balance decrease?
================================================

Your balance is the instantaneous sum of your deposited principal and your unclaimed profit at the moment that you claim and immediately redeposit the profit into the pool.

At some points, the balance may decrease because the price of tokens relevant to the pool may have fluctuated.

How does the timer work?
================================================

Withdraws within 72h will have a 0.5% fee applied. This timer is reset every time you make a new deposit. Claiming rewards on the pools that allow it does not reset the timer.

How is the profit calculated?
================================================

At the moment of withdrawal (exit & claim) the performance fee is exactly calculated (30% of profits) and BUNNY is rewarded.

Is there slippage using the ZAP function?
================================================

ZAP is based on PancakeSwap’s swap feature so we can’t control the slippage/IL associated with it.

Why is my TVL or Deposit showing 0?
================================================

If you see 0 tvl or 0 deposit just try refreshing your browser and reconnecting your wallet.

Why am I getting failing transactions?
================================================

Unfortunately this seems to be a common issue on the chain lately. Try increasing by 5 GWEI. When this happens, it is probably happening on PancakeSwap (and other projects as well), and it is generally fine if you use 18-20 GWEI.

What is Bunny’s Roadmap?
================================================

Please view our roadmap on notion: http://bit.ly/bunny_roadmap
We have plans on expanding the variety of pools available, creating single asset vaults, arbitrage, and much more!

Who is behind Bunny?
================================================

The Bunny Project was created by a team of developers and blockchain specialists! Like all other Yield Aggregator Projects, we believe our code is who we are! Thus, we will ensure to provide full transparency and let our code speak for itself.

Is Bunny Safe?
================================================

Like all DeFi Projects, it is important not to trust but to verify the legitimacy of each project by confirming the data/code. As such we are providing full transparency by releasing all the code/data required to confirm that Bunny runs smoothly. Check out our github: https://github.com/PancakeBunny-finance

Is Bunny Audited?
================================================

Yes, Haechi Labs has completed the first audit. The results were extremely positive! The audit highlighted no critical or major issues, and two minor issues. One of the minor issues has been found on most well-known governance tokens and will not expose much issue/security risk to normal end-users. The other minor issue is an intended behavior.

Please see the report `here <https://github.com/PancakeBunny-finance/Bunny/blob/main/audits/%5BHAECHI%20AUDIT%5D%20PancakeBunny%20Smart%20Contract%20Audit%20Report%20ver%202.0.pdf>`_

APR & APY
================================================

Let’s assume the APR of the CAKE farm is 365%. This means that on average if we divide 365% by 365 days, we get a daily return of 1%. Now since Bunny compounds this 1%, we can estimate the compounded APR using the following calculation: (1+0.01)^365 - 1 = 3678% Keep in mind that this is an assumption that only holds true if the APR of CAKE farm stays constant through one year. However, this is obviously not the case since the APY also changes by the second. We can use the same calculation for the rest of the Farms as well! Just divide the APR by 365, which would be the average daily yield. (1+daily yield)^365 -1 = Compounded APY.

The new maximizer farms put the daily yields from the Farms, into the CAKE compounding pools. The Stable Coin-BNB Farms have a current APY of 30%, but if we use the maximizer farms the APY increases to about 150%. This strategy is truly unique and advantageous since the principal investment does not get touched, and only the extra yields from the farm get invested in the more volatile, high risk-high reward CAKE pool.

How is the APY Calculated?
================================================

The APY on pool screen is the sum of the following rates:

[Pool APY]
This the APY from the auto-compounding rate on the token of the pool you are staking.

[Bunny APY]
This is the APY in BUNNY rewards you will receive based on the 30% Performance Fee collected from your total pool profits.

[Swap APY]
This is an estimation of the increase in value of your LP tokens due to the rewards from the swap fees on PancakeSwap.

How often do Auto-Compounding Pools Compound?
================================================
The auto compounding varies from pool to pool. The current frequencies are:
- Cake and Cake Maximizers: At least every 2 hours (harvesting when any user deposit or withdraws)
- CAKE-BNB flips: Every 2 hours
- Other flip pools: Every 4 hours
- Single-Asset "Smart" Vaults: Every 2 hours

Why is there a Claim Button on Auto-Compounding Pools?
================================================
The Claim button is an extra option for those that wish to use it. It was a suggested and voted on by the users.

All pools that have "auto-compounding" or "compound cake recursively" in their description are auto-compounding the profits. The BUNNY figure that appears on the Profit line is what you would receive at the moment you choose to Claim.

