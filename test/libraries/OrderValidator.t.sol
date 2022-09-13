// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {OrderInfo} from "../../src/interfaces/ReactorStructs.sol";
import {OrderValidator} from "../../src/lib/OrderValidator.sol";
import {MockValidationContract} from "../../src/test/MockValidationContract.sol";
import {MockOrderValidator} from "../../src/test/MockOrderValidator.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";

contract OrderValidatorTest is Test {
    using OrderInfoBuilder for OrderInfo;

    MockOrderValidator validator;

    function setUp() public {
        validator = new MockOrderValidator();
    }

    function testInvalidReactor() public {
        vm.expectRevert(OrderValidator.InvalidReactor.selector);
        validator.validate(OrderInfoBuilder.init(address(0)));
    }

    function testDeadlinePassed() public {
        vm.expectRevert(OrderValidator.DeadlinePassed.selector);
        uint256 timestamp = block.timestamp;
        vm.warp(timestamp + 100);
        validator.validate(OrderInfoBuilder.init(address(validator)).withDeadline(block.timestamp - 1));
    }

    function testValidationContractInvalid() public {
        MockValidationContract validationContract = new MockValidationContract();
        validationContract.setValid(false);
        vm.expectRevert(OrderValidator.InvalidOrder.selector);
        validator.validate(
            OrderInfoBuilder.init(address(validator)).withDeadline(block.timestamp).withValidationContract(
                address(validationContract)
            )
        );
    }

    function testValid() public view {
        validator.validate(OrderInfoBuilder.init(address(validator)));
    }

    function testValidationContractValid() public {
        MockValidationContract validationContract = new MockValidationContract();
        validationContract.setValid(true);
        validator.validate(
            OrderInfoBuilder.init(address(validator)).withValidationContract(address(validationContract))
        );
    }

    function testUpdateFilled() public {
        bytes32 orderHash = keccak256("test");
        validator.updateFilled(orderHash);
        assertTrue(validator.getOrderStatus(orderHash).isFilled);
        assertFalse(validator.getOrderStatus(orderHash).isCancelled);
    }

    function testUpdateFilledWhenCancelled() public {
        bytes32 orderHash = keccak256("test");
        validator.updateCancelled(orderHash);
        vm.expectRevert(OrderValidator.OrderCancelled.selector);
        validator.updateFilled(orderHash);
    }

    function testUpdateFilledWhenAlreadyFilled() public {
        bytes32 orderHash = keccak256("test");
        validator.updateFilled(orderHash);
        vm.expectRevert(OrderValidator.OrderAlreadyFilled.selector);
        validator.updateFilled(orderHash);
    }

    function testUpdateCancelled() public {
        bytes32 orderHash = keccak256("test");
        validator.updateCancelled(orderHash);
        assertFalse(validator.getOrderStatus(orderHash).isFilled);
        assertTrue(validator.getOrderStatus(orderHash).isCancelled);
    }

    function testUpdateCancelledWhenAlreadyCancelled() public {
        bytes32 orderHash = keccak256("test");
        validator.updateCancelled(orderHash);
        vm.expectRevert(OrderValidator.OrderCancelled.selector);
        validator.updateCancelled(orderHash);
    }

    function testUpdateCancelledWhenAlreadyFilled() public {
        bytes32 orderHash = keccak256("test");
        validator.updateFilled(orderHash);
        vm.expectRevert(OrderValidator.OrderAlreadyFilled.selector);
        validator.updateCancelled(orderHash);
    }
}
