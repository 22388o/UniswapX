// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {SignedOrder, OrderInfo} from "../../src/base/ReactorStructs.sol";
import {NATIVE} from "../../src/lib/CurrencyLibrary.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {ProtocolFees} from "../../src/base/ProtocolFees.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {DutchLimitOrderLib} from "../../src/lib/DutchLimitOrderLib.sol";
import {
    DutchLimitOrderReactor,
    DutchLimitOrder,
    DutchInput,
    DutchOutput
} from "../../src/reactors/DutchLimitOrderReactor.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";

contract ProtocolFeesTest is Test, DeployPermit2, GasSnapshot, PermitSignature {
    using OrderInfoBuilder for OrderInfo;

    address constant PROTOCOL_FEE_RECIPIENT = address(2);
    address constant GOVERNANCE = address(3);
    address constant INTERFACE_FEE_RECIPIENT = address(4);
    uint256 constant ONE = 10 ** 18;

    MockERC20 tokenIn1;
    MockERC20 tokenOut1;
    MockERC20 tokenOut2;
    uint256 makerPrivateKey1;
    address maker1;
    uint256 makerPrivateKey2;
    address maker2;
    DutchLimitOrderReactor reactor;
    IAllowanceTransfer permit2;
    MockFillContract fillContract;

    function setUp() public {
        tokenIn1 = new MockERC20("tokenIn1", "IN1", 18);
        tokenOut1 = new MockERC20("tokenOut1", "OUT1", 18);
        tokenOut2 = new MockERC20("tokenOut2", "OUT2", 18);
        fillContract = new MockFillContract();
        makerPrivateKey1 = 0x12341234;
        maker1 = vm.addr(makerPrivateKey1);
        makerPrivateKey2 = 0x12341235;
        maker2 = vm.addr(makerPrivateKey2);
        permit2 = IAllowanceTransfer(deployPermit2());
        reactor = new DutchLimitOrderReactor(address(permit2), GOVERNANCE, PROTOCOL_FEE_RECIPIENT);
        tokenIn1.forceApprove(maker1, address(permit2), type(uint256).max);
        tokenIn1.forceApprove(maker2, address(permit2), type(uint256).max);

        vm.prank(GOVERNANCE);
        reactor.setProtocolFees(address(tokenOut1), 5);
        vm.prank(GOVERNANCE);
        reactor.setProtocolFees(address(tokenOut2), 1);
    }

    // outputs array: [0.9995 tokenOut1 -> maker1, 0.0005 tokenOut1 -> protocol]. Should succeed
    function test1OutputWithProtocolFee() public {
        tokenIn1.mint(address(maker1), ONE);
        tokenOut1.mint(address(fillContract), ONE);

        DutchOutput[] memory dutchOutputs = new DutchOutput[](2);
        dutchOutputs[0] = DutchOutput(address(tokenOut1), ONE * 9995 / 10000, ONE * 9995 / 10000, maker1);
        dutchOutputs[1] = DutchOutput(address(tokenOut1), ONE * 5 / 10000, ONE * 5 / 10000, PROTOCOL_FEE_RECIPIENT);
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), ONE, ONE),
            outputs: dutchOutputs
        });
        snapStart("ProtocolFeesTest1OutputWithProtocolFee");
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey1, address(permit2), order)),
            address(fillContract),
            bytes("")
        );
        snapEnd();
        assertEq(tokenIn1.balanceOf(address(fillContract)), ONE);
        assertEq(tokenOut1.balanceOf(address(fillContract)), 0);
        assertEq(tokenOut1.balanceOf(maker1), ONE * 9995 / 10000);
        assertEq(tokenOut1.balanceOf(PROTOCOL_FEE_RECIPIENT), ONE * 5 / 10000);
    }

    // outputs array: [0.999 tokenOut1 -> maker1, 0.0005 tokenOut1 -> protocol, 0.0005 tokenOut1 -> interface].
    // Should succeed
    function test1OutputWithProtocolFeeAndInterfaceFee() public {
        tokenIn1.mint(address(maker1), ONE);
        tokenOut1.mint(address(fillContract), ONE);

        DutchOutput[] memory dutchOutputs = new DutchOutput[](3);
        dutchOutputs[0] = DutchOutput(address(tokenOut1), ONE * 9990 / 10000, ONE * 9990 / 10000, maker1);
        dutchOutputs[1] = DutchOutput(address(tokenOut1), ONE * 5 / 10000, ONE * 5 / 10000, PROTOCOL_FEE_RECIPIENT);
        dutchOutputs[2] = DutchOutput(address(tokenOut1), ONE * 5 / 10000, ONE * 5 / 10000, INTERFACE_FEE_RECIPIENT);
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), ONE, ONE),
            outputs: dutchOutputs
        });
        snapStart("ProtocolFeesTest1OutputWithProtocolFeeAndInterfaceFee");
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey1, address(permit2), order)),
            address(fillContract),
            bytes("")
        );
        snapEnd();
        assertEq(tokenIn1.balanceOf(address(fillContract)), ONE);
        assertEq(tokenOut1.balanceOf(address(fillContract)), 0);
        assertEq(tokenOut1.balanceOf(maker1), ONE * 9990 / 10000);
        assertEq(tokenOut1.balanceOf(PROTOCOL_FEE_RECIPIENT), ONE * 5 / 10000);
        assertEq(tokenOut1.balanceOf(INTERFACE_FEE_RECIPIENT), ONE * 5 / 10000);
    }

    // outputs array: [0.999 tokenOut1 -> maker1, 0.0004 tokenOut1 -> protocol, 0.0005 tokenOut1 -> interface].
    // Should fail because we expect 5bps protocol fee
    function test1OutputWithProtocolFeeAndInterfaceFeeInsufficientProtocolFee() public {
        tokenIn1.mint(address(maker1), ONE);
        tokenOut1.mint(address(fillContract), ONE);

        DutchOutput[] memory dutchOutputs = new DutchOutput[](3);
        dutchOutputs[0] = DutchOutput(address(tokenOut1), ONE * 9990 / 10000, ONE * 9990 / 10000, maker1);
        dutchOutputs[1] = DutchOutput(address(tokenOut1), ONE * 4 / 10000, ONE * 4 / 10000, PROTOCOL_FEE_RECIPIENT);
        dutchOutputs[2] = DutchOutput(address(tokenOut1), ONE * 5 / 10000, ONE * 5 / 10000, INTERFACE_FEE_RECIPIENT);
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), ONE, ONE),
            outputs: dutchOutputs
        });
        vm.expectRevert(ProtocolFees.InsufficientProtocolFee.selector);
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey1, address(permit2), order)),
            address(fillContract),
            bytes("")
        );
    }

    // outputs array: [0.0005 tokenOut1 -> protocol, 0.999 tokenOut1 -> maker1, 0.0005 tokenOut1 -> interface].
    // The same as `test1OutputWithProtocolFeeAndInterfaceFee`, but put the protocol fee first in the array. Ensure
    // the order of the protocol fee in the outputs array has no impact on success.
    function test1OutputWithProtocolFeeAndInterfaceFeeChangeOrder() public {
        tokenIn1.mint(address(maker1), ONE);
        tokenOut1.mint(address(fillContract), ONE);

        DutchOutput[] memory dutchOutputs = new DutchOutput[](3);
        dutchOutputs[1] = DutchOutput(address(tokenOut1), ONE * 9990 / 10000, ONE * 9990 / 10000, maker1);
        dutchOutputs[0] = DutchOutput(address(tokenOut1), ONE * 5 / 10000, ONE * 5 / 10000, PROTOCOL_FEE_RECIPIENT);
        dutchOutputs[2] = DutchOutput(address(tokenOut1), ONE * 5 / 10000, ONE * 5 / 10000, INTERFACE_FEE_RECIPIENT);
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), ONE, ONE),
            outputs: dutchOutputs
        });
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey1, address(permit2), order)),
            address(fillContract),
            bytes("")
        );
        assertEq(tokenIn1.balanceOf(address(fillContract)), ONE);
        assertEq(tokenOut1.balanceOf(address(fillContract)), 0);
        assertEq(tokenOut1.balanceOf(maker1), ONE * 9990 / 10000);
        assertEq(tokenOut1.balanceOf(PROTOCOL_FEE_RECIPIENT), ONE * 5 / 10000);
        assertEq(tokenOut1.balanceOf(INTERFACE_FEE_RECIPIENT), ONE * 5 / 10000);
    }

    // outputs array:
    // 0.999 tokenOut1 -> maker1
    // 0.0005 tokenOut1 -> protocol
    // 0.0005 tokenOut1 -> interface
    // 0.9999 tokenOut2 -> maker1
    // 0.0001 tokenOut2 -> protocol
    function test2OutputsWithProtocolFees() public {
        tokenIn1.mint(address(maker1), ONE);
        tokenOut1.mint(address(fillContract), ONE);
        tokenOut2.mint(address(fillContract), ONE);

        DutchOutput[] memory dutchOutputs = new DutchOutput[](5);
        dutchOutputs[0] = DutchOutput(address(tokenOut1), ONE * 9990 / 10000, ONE * 9990 / 10000, maker1);
        dutchOutputs[1] = DutchOutput(address(tokenOut1), ONE * 5 / 10000, ONE * 5 / 10000, PROTOCOL_FEE_RECIPIENT);
        dutchOutputs[2] = DutchOutput(address(tokenOut1), ONE * 5 / 10000, ONE * 5 / 10000, INTERFACE_FEE_RECIPIENT);
        dutchOutputs[3] = DutchOutput(address(tokenOut2), ONE * 9999 / 10000, ONE * 9999 / 10000, maker1);
        dutchOutputs[4] = DutchOutput(address(tokenOut2), ONE * 1 / 10000, ONE * 1 / 10000, PROTOCOL_FEE_RECIPIENT);
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), ONE, ONE),
            outputs: dutchOutputs
        });
        snapStart("ProtocolFeesTest2OutputsWithProtocolFees");
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey1, address(permit2), order)),
            address(fillContract),
            bytes("")
        );
        snapEnd();
        assertEq(tokenIn1.balanceOf(address(fillContract)), ONE);
        assertEq(tokenOut1.balanceOf(address(fillContract)), 0);
        assertEq(tokenOut2.balanceOf(address(fillContract)), 0);
        assertEq(tokenOut1.balanceOf(maker1), ONE * 9990 / 10000);
        assertEq(tokenOut1.balanceOf(PROTOCOL_FEE_RECIPIENT), ONE * 5 / 10000);
        assertEq(tokenOut1.balanceOf(INTERFACE_FEE_RECIPIENT), ONE * 5 / 10000);
        assertEq(tokenOut2.balanceOf(maker1), ONE * 9999 / 10000);
        assertEq(tokenOut2.balanceOf(PROTOCOL_FEE_RECIPIENT), ONE * 1 / 10000);
    }

    // outputs array:
    // 0.999 tokenOut1 -> maker1
    // 0.0005 tokenOut1 -> protocol
    // 0.0005 tokenOut1 -> interface
    // 0.9999 tokenOut2 -> maker1
    // 1 / 20000 tokenOut2 -> protocol (this is insufficient as it is < 1 bps of total tokenOut2 outputs)
    // This test will fail because of insufficient protocol fee for tokenOut2
    function test2OutputsWithProtocolFeesInsufficientProtocolFeeTokenOut2() public {
        tokenIn1.mint(address(maker1), ONE);
        tokenOut1.mint(address(fillContract), ONE);
        tokenOut2.mint(address(fillContract), ONE);

        DutchOutput[] memory dutchOutputs = new DutchOutput[](5);
        dutchOutputs[0] = DutchOutput(address(tokenOut1), ONE * 9990 / 10000, ONE * 9990 / 10000, maker1);
        dutchOutputs[1] = DutchOutput(address(tokenOut1), ONE * 5 / 10000, ONE * 5 / 10000, PROTOCOL_FEE_RECIPIENT);
        dutchOutputs[2] = DutchOutput(address(tokenOut1), ONE * 5 / 10000, ONE * 5 / 10000, INTERFACE_FEE_RECIPIENT);
        dutchOutputs[3] = DutchOutput(address(tokenOut2), ONE * 9999 / 10000, ONE * 9999 / 10000, maker1);
        dutchOutputs[4] = DutchOutput(address(tokenOut2), ONE * 1 / 20000, ONE * 1 / 20000, PROTOCOL_FEE_RECIPIENT);
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), ONE, ONE),
            outputs: dutchOutputs
        });
        vm.expectRevert(ProtocolFees.InsufficientProtocolFee.selector);
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey1, address(permit2), order)),
            address(fillContract),
            bytes("")
        );
    }
}
