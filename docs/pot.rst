************************
Pot
************************

What Is a Bunny Pot?
================================================

A Bunny Pot is a no-loss “jackpot” pool similar to the service pioneered by Pool Together. Users stake tokens to a Bunny Pot during an initial Staking Period (e.g. the first 24 hours). At the end of this initial Period, the Pot is closed to further staking and for the next 6 days (the Farming Period), the Pot farms all of the pooled assets to generate a pooled yield. (Note: technically, the Bunny Pot begins staking tokens as soon as they are staked, but in the interests of simplicity, we call the next 6 days after staking closes the Farming Period).

At the end of the Farming Period, one user is randomly selected as the winner, based on a composite weighting of the Number of Tokens they have contributed to the Bunny Pot times the Speed multiple (S) and the History multiple (H) (so that the composite weighting = # Tokens X S X H).

What Does No-Loss Mean? Can I Lose Any of the Tokens I Stake?
================================================

Bunny Pots are no-loss pools in the sense that your principal is never at risk. At the end of the Farming Period, everyone who participates will be returned their initial stake. No one is at risk of losing any of the tokens they stake because Bunny Pots operate just like all of our other pools. The difference lies in how the profits are distributed.

So Then Where Do Bunny Pot Pool Profits Go?
================================================

Essentially, Bunny Pot pool profits go to the winner, with some portion reserved for PancakeBunny’s program to buy back BUNNY tokens. For launch purposes, 90% of all of the profits go to the winner, and 10% go to the Community Treasury to buy back BUNNY on the open market. This ratio may be adjusted from time to time as Team Bunny monitors user behavior and buy back performance to maximize the benefit to the PancakeBunny Community.

Team Bunny “Jackpot” Contribution
================================================

At launch, Team Bunny is contributing a big bag of tokens to each Bunny Pot to grow the total “jackpot”. At launch and until the Bunny Pots are organically sufficiently large to obviate the need for Team Bunny to seed the Pots, Team Bunny is committed to contributing this initial stake to make the size of the “jackpots” worth the opportunity cost of users staking to the pools.

NONE of Team Bunny’s tokens is eligible to win. Their sole function is to contribute to the size of the pool being farmed. In other words, Team Bunny’s tokens are “whitelisted” and are ineligible to win and are therefore not counted in calculations of probabilities. Their only effect on the outcome is to INCREASE the number of tokens that are farmed by the Bunny Pot to INCREASE the size of the “jackpot” that goes to the winning user.

Bunny Pot Math — “Jackpot” Calculations
================================================

Suppose the Team has staked 10,000 CAKE to the CAKE Bunny Pot to increase the eventual “jackpot”.

And suppose users stake 1,000 CAKE to the Bunny Pot during the Staking Period, so that the total number of CAKE staked to the Bunny Pot is 11,000 CAKE (Team Tokens plus Community Tokens).

Then, throughout the Farming Period, and at current APY’s, the Bunny Pot profit would generate a total of around 220 CAKE in profits.

Suppose you were a user who had staked 10 CAKE to the Bunny Pot in this scenario. If you had instead staked 10 CAKE to the CAKE pool on your own, you would expect to have earned around 0.2 CAKE by the end of the Farming Period.

But by staking your 10 CAKE to the Bunny Pot, you are guaranteed the return of your original stake just as in standard pools, and you have a chance to win the “jackpot” of 90% of the entire Bunny Pot yield of 220 CAKE. This is equivalent to a 990x multiple on the earnings you would expect to have earned if you had staked your 10 CAKE on your own.

Bunny Pot Periods
================================================

Before diving into how Bunny Pot Weighted Odds work, let’s take a look at the different Periods in the status of a given Bunny Pot. These Periods operate as follows over a 7 day period:

- Staking Period (the first 24 hours): This is the period during which you can stake tokens to the Bunny Pot. (BUNNY POT STATUS = UNLOCKED)

- Farming Period (the 6 days following the Staking Period)*: This is the period during which the Bunny Pot is closed to any more staking, and during which the Bunny Pot will farm profits using the total pooled assets of the Bunny Pot (including the contribution from Team Bunny!). (BUNNY POT STATUS = FARMING)

- Return Period (the period after the Farming Period ends): At the end of the Farming Period, open the Bunny Pot to see if you have won! If you have won, you will receive your original stake, plus 90% of the profits farmed by the entire pool over the course of the Farming Period! If you haven’t won, don’t worry, your stake will be returned to you because Bunny Pots are NO-LOSS! (BUNNY POT STATUS = COLLECT)

Understanding Bunny Pot Parameters
================================================

Your final odds are determined by your Weighted Contribution (WC) to the Bunny Pot divided by the Total Weighted Contribution (TWC) of all of the users staked in the Bunny Pot.

Weighted Contribution (WC)

Your WC is determined by the following parameters: the Amount (A) or number of tokens you stake, the Speed (S) multiplier derived from how early you contribute your stake during the Staking Period, and the History (H) multiplier derived from your win/loss history.

Amount (A): Suppose you staked 10 CAKE, as in the example above. Then:
A = 10, the number of CAKE you staked in the Bunny Pot

Speed (S): The Speed multiplier, S, is determined by the following table.
S = 2.8 if you stake between Hour 0 and Hour 4 of the Staking Period
S = 2.4 if you stake between Hour 4 and Hour 8 of the Staking Period
S = 2.0 if you stake between Hour 8 and Hour 12 of the Staking Period
S = 1.6 if you stake between Hour 12 and Hour 16 of the Staking Period
S = 1.2 if you stake between Hour 16 and Hour 20 of the Staking Period, and
S = 0.8 if you stake between Hour 20 and Hour 24 of the Staking PeriodWithin 20 to 24 hours: x0.8

History (H): Your History multiplier increases your chances of winning the longer you have gone without winning a Bunny Pot.?
H = 1 if you have not won a single Pot in your previous 0 to 4 Pots;
H = 2 if you have not won in your previous 5 to 8 Pots;
H = 3 if you have not won in your previous 9 to 12 Pots; and
H = 4 if you have not won in your previous more than 13 Pots.

Stake Limits: What Are the Min Stake and Max Stake?
For launch purposes, we have set the following stake limits:

Minimum Stake: Min Stake = 1 Token

Maximum Stake: Max Stake = 100 Tokens

Bunny Pot Math — Calculating Your Odds
================================================

As in the above “jackpot” calculation, suppose the Team Contribution = 10,000 CAKE and the total Community Contribution = 1,000 CAKE, of which you have contributed 10 CAKE.

Suppose further that you staked your CAKE during the first 4 hours of the Staking Period, and that you had not won a single Pot in the last 10 times that you had participated.

Then your Weighted Contribution (WC) would be calculated as follows:

WC = A x S x H = 10 x 2.8 x 3 = 84

To calculate your odds, let us assume that the average Speed multiplier for the remaining CAKE staked to the pool by the Community is S = 2.6 and the average History multiplier for the remaining Community stake is H = 1.001.

Then the Total Weighted Contribution (TWC) of the rest of the Pool is calculated as follows:

TWC = WC + 990 x 2.6 x 1.001 = 84 + 2,576.574 = 2,660.574

In which case, your Final Odds (FO) would be calculated as follows:

FO = WC / TWC = ~3.16%

Because the user, in this case, staked quickly and hasn’t won a single Pot in the last 10 Pots, they have increased their odds by over 3x versus their simple unweighted share of the total token pool (1%).

Finally, your Expected Return for Participating (ERP), in this scenario, would be calculated as follows:

ERP = 220 CAKE * FO = ~7 CAKE

In this scenario, your ERP = ~7 CAKE = ~34.7x 0.2 CAKE (your expected return if you farmed your 10 CAKE on your own). So your ERP is ~35x your ERP if you staked your CAKE on your own.

The above description is meant to illustrate the functioning of the construct. For a more formal statement, please see the following:

.. image:: /images/bunnypot_math.png
  :width: 260
  :align: center
  :alt: BunnyPot Math

