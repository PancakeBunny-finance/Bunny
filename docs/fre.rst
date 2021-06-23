************************
Floating Rate Emission
************************

Given both the necessity to generate meaningful rewards yet also continually improve the current token dynamics, we implemented a mechanism for a floating rate emission (FRE).The initial FRE is 36% — 30% Performance Fee, 6% BUNNY mint.

When the relative price of BUNNY goes below 1/15 of BNB (or an otherwise optimal threshold), the system will adjust to do the following:

1. The system uses the 30% Performance Fee to buy BUNNY at the market price.
2. An amount of BUNNY equal to 6% of the Claim is minted and sent to the user

On the other hand, when the BUNNY/BNB Ratio is over the above optimal BNB threshold, initiated claims will perform as originally designed, with the Performance Fee going to the Bunny Pool and the newly minted BUNNY delivered to the user.

Start Date: 17 June 2021