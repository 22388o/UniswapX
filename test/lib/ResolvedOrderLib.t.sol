// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {OrderInfo, ResolvedOrder} from "../../src/base/ReactorStructs.sol";
import {ResolvedOrderLib} from "../../src/lib/ResolvedOrderLib.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {MockResolvedOrderLib} from "../util/mock/MockResolvedOrderLib.sol";
import {MockValidationContract} from "../util/mock/MockValidationContract.sol";
import {ExclusiveFillerValidation} from "../../src/sample-validation-contracts/ExclusiveFillerValidation.sol";

contract ResolvedOrderLibTest is Test {
    using OrderInfoBuilder for OrderInfo;

    MockResolvedOrderLib private resolvedOrderLib;
    ResolvedOrder private mockResolvedOrder;

    function setUp() public {
        resolvedOrderLib = new MockResolvedOrderLib();
    }

    function testInvalidReactor() public {
        mockResolvedOrder.info = OrderInfoBuilder.init(address(0));

        vm.expectRevert(ResolvedOrderLib.InvalidReactor.selector);
        resolvedOrderLib.validate(mockResolvedOrder, address(0));
    }

    function testDeadlinePassed() public {
        uint256 timestamp = block.timestamp;
        vm.warp(timestamp + 100);
        mockResolvedOrder.info = OrderInfoBuilder.init(address(resolvedOrderLib)).withDeadline(block.timestamp - 1);

        vm.expectRevert(ResolvedOrderLib.DeadlinePassed.selector);
        resolvedOrderLib.validate(mockResolvedOrder, address(0));
    }

    function testValid() public {
        mockResolvedOrder.info = OrderInfoBuilder.init(address(resolvedOrderLib));
        resolvedOrderLib.validate(mockResolvedOrder, address(0));
    }

    function testValidationContractInvalid() public {
        MockValidationContract validationContract = new MockValidationContract();
        validationContract.setValid(false);
        vm.expectRevert(MockValidationContract.ValidationFailed.selector);
        mockResolvedOrder.info =
            OrderInfoBuilder.init(address(resolvedOrderLib)).withValidationContract(address(validationContract));
        resolvedOrderLib.validate(mockResolvedOrder, address(0));
    }

    function testValidationContractValid() public {
        MockValidationContract validationContract = new MockValidationContract();
        validationContract.setValid(true);
        mockResolvedOrder.info =
            OrderInfoBuilder.init(address(resolvedOrderLib)).withValidationContract(address(validationContract));
        resolvedOrderLib.validate(mockResolvedOrder, address(0));
    }

    function testExclusiveFillerValidationInvalidFiller() public {
        vm.warp(900);
        ExclusiveFillerValidation exclusiveFillerValidation = new ExclusiveFillerValidation();
        mockResolvedOrder.info = OrderInfoBuilder.init(address(resolvedOrderLib)).withValidationContract(
            address(exclusiveFillerValidation)
        ).withValidationData(abi.encode(address(0x123), 1000, 0));
        vm.expectRevert(MockValidationContract.ValidationFailed.selector);
        resolvedOrderLib.validate(mockResolvedOrder, address(0x234));
    }

    // The filler is not the same filler as the filler encoded in validationData, but we are past the last
    // exclusive timestamp, so it will not revert.
    function testExclusiveFillerValidationInvalidFillerPastTimestamp() public {
        vm.warp(900);
        ExclusiveFillerValidation exclusiveFillerValidation = new ExclusiveFillerValidation();
        mockResolvedOrder.info = OrderInfoBuilder.init(address(resolvedOrderLib)).withValidationContract(
            address(exclusiveFillerValidation)
        ).withValidationData(abi.encode(address(0x123), 888, 0));
        resolvedOrderLib.validate(mockResolvedOrder, address(0x234));
    }

    // Kind of a pointless test, but ensure the specified filler can fill after last exclusive timestamp still.
    function testExclusiveFillerValidationValidFillerPastTimestamp() public {
        vm.warp(900);
        ExclusiveFillerValidation exclusiveFillerValidation = new ExclusiveFillerValidation();
        mockResolvedOrder.info = OrderInfoBuilder.init(address(resolvedOrderLib)).withValidationContract(
            address(exclusiveFillerValidation)
        ).withValidationData(abi.encode(address(0x123), 1000, 0));
        resolvedOrderLib.validate(mockResolvedOrder, address(0x123));
    }
}
