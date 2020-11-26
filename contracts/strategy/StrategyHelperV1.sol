// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/BEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";

import "../interfaces/IPancakeFactory.sol";
import "../interfaces/IPancakePair.sol";
import "../strategy/IMasterChef.sol";
import "./IStrategy.sol";
import "./IStrategyHelper.sol";

// no storage
// There are only calculations for apy, tvl, etc.
contract StrategyHelperV1 is IStrategyHelper {
    using SafeMath for uint;
    address private constant CAKE_POOL = 0xA527a61703D82139F8a06Bc30097cC9CAA2df5A6;
    address private constant BNB_BUSD_POOL = 0x1B96B92314C44b159149f7E0303511fB2Fc4774f;

    IBEP20 private constant WBNB = IBEP20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    IBEP20 private constant CAKE = IBEP20(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);
    IBEP20 private constant BUSD = IBEP20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);

    IMasterChef private constant master = IMasterChef(0x73feaa1eE314F8c655E354234017bE2193C9E24E);
    IPancakeFactory private constant factory = IPancakeFactory(0xBCfCcbde45cE874adCB698cC183deBcF17952812);

    function tokenPriceInBNB(address _token) override view public returns(uint) {
        address pair = factory.getPair(_token, address(WBNB));
        uint decimal = uint(BEP20(_token).decimals());

        return WBNB.balanceOf(pair).mul(10**decimal).div(IBEP20(_token).balanceOf(pair));
    }

    function cakePriceInBNB() override view public returns(uint) {
        return WBNB.balanceOf(CAKE_POOL).mul(1e18).div(CAKE.balanceOf(CAKE_POOL));
    }

    function bnbPriceInUSD() override view public returns(uint) {
        return BUSD.balanceOf(BNB_BUSD_POOL).mul(1e18).div(WBNB.balanceOf(BNB_BUSD_POOL));
    }

    function flipPriceInBNB(address _flip) override view public returns(uint) {
        return tvlInBNB(_flip, 1e18);
    }

    function flipPriceInUSD(address _flip) override view public returns(uint) {
        return tvl(_flip, 1e18);
    }

    function cakePerYearOfPool(uint pid) view public returns(uint) {
        (, uint allocPoint,,) = master.poolInfo(pid);
        return master.cakePerBlock().mul(blockPerYear()).mul(allocPoint).div(master.totalAllocPoint());
    }

    function blockPerYear() pure public returns(uint) {
        // 86400 / 3 * 365
        return 10512000;
    }

    function profitOf(IBunnyMinter minter, address flip, uint amount) override external view returns (uint _usd, uint _bunny, uint _bnb) {
        _usd = tvl(flip, amount);
        if (address(minter) == address(0)) {
            _bunny = 0;
        } else {
            uint performanceFee = minter.performanceFee(_usd);
            _usd = _usd.sub(performanceFee);
            uint bnbAmount = performanceFee.mul(1e18).div(bnbPriceInUSD());
            _bunny = minter.amountBunnyToMint(bnbAmount);
        }
        _bnb = 0;
    }

    // apy() = cakePrice * (cakePerBlock * blockPerYear * weight) / PoolValue(=WBNB*2)
    function _apy(uint pid) view private returns(uint) {
        (address token,,,) = master.poolInfo(pid);
        uint poolSize = tvl(token, IBEP20(token).balanceOf(address(master))).mul(1e18).div(bnbPriceInUSD());
        return cakePriceInBNB().mul(cakePerYearOfPool(pid)).div(poolSize);
    }

    function apy(IBunnyMinter, uint pid) override view public returns(uint _usd, uint _bunny, uint _bnb) {
        _usd = compoundingAPY(pid, 1 days);
        _bunny = 0;
        _bnb = 0;
    }

    function tvl(address _flip, uint amount) override public view returns (uint) {
        if (_flip == address(CAKE)) {
            return cakePriceInBNB().mul(bnbPriceInUSD()).mul(amount).div(1e36);
        }
        address _token0 = IPancakePair(_flip).token0();
        address _token1 = IPancakePair(_flip).token1();
        if (_token0 == address(WBNB) || _token1 == address(WBNB)) {
            uint bnb = WBNB.balanceOf(address(_flip)).mul(amount).div(IBEP20(_flip).totalSupply());
            uint price = bnbPriceInUSD();
            return bnb.mul(price).div(1e18).mul(2);
        }

        uint balanceToken0 = IBEP20(_token0).balanceOf(_flip);
        uint price = tokenPriceInBNB(_token0);
        return balanceToken0.mul(price).div(1e18).mul(bnbPriceInUSD()).div(1e18).mul(2).mul(amount).div(IBEP20(_flip).totalSupply());
    }

    function tvlInBNB(address _flip, uint amount) override public view returns (uint) {
        if (_flip == address(CAKE)) {
            return cakePriceInBNB().mul(amount).div(1e18);
        }
        address _token0 = IPancakePair(_flip).token0();
        address _token1 = IPancakePair(_flip).token1();
        if (_token0 == address(WBNB) || _token1 == address(WBNB)) {
            uint bnb = WBNB.balanceOf(address(_flip)).mul(amount).div(IBEP20(_flip).totalSupply());
            return bnb.mul(2);
        }

        uint balanceToken0 = IBEP20(_token0).balanceOf(_flip);
        uint price = tokenPriceInBNB(_token0);
        return balanceToken0.mul(price).div(1e18).mul(2).mul(amount).div(IBEP20(_flip).totalSupply());
    }

    function compoundingAPY(uint pid, uint compoundUnit) override view public returns(uint) {
        uint __apy = _apy(pid);
        uint compoundTimes = 365 days / compoundUnit;
        uint unitAPY = 1e18 + (__apy / compoundTimes);
        uint result = 1e18;

        for(uint i=0; i<compoundTimes; i++) {
            result = (result * unitAPY) / 1e18;
        }

        return result - 1e18;
    }
}