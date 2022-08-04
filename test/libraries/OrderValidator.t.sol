// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {OrderInfo} from "../../src/interfaces/ReactorStructs.sol";
import {OrderValidator} from "../../src/lib/OrderValidator.sol";
import {MockValidationContract} from "../../src/test/MockValidationContract.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";

contract OrderValidatorTest is Test, GasSnapshot {
    using OrderInfoBuilder for OrderInfo;

    OrderValidator validator;

    function setUp() public {
        validator = new OrderValidator();
    }

    function testInvalidReactor() public {
        vm.expectRevert(OrderValidator.InvalidReactor.selector);
        validator.validateOrderInfo(OrderInfoBuilder.init(address(0)));
    }

    function testDeadlinePassed() public {
        vm.expectRevert(OrderValidator.DeadlinePassed.selector);
        uint256 timestamp = block.timestamp;
        vm.warp(timestamp + 100);
        validator.validateOrderInfo(
            OrderInfoBuilder.init(address(validator)).withDeadline(block.timestamp - 1)
        );
    }

    function testValidationContractInvalid() public {
        MockValidationContract validationContract = new MockValidationContract();
        validationContract.setValid(false);
        vm.expectRevert(OrderValidator.InvalidOrder.selector);
        validator.validateOrderInfo(
            OrderInfoBuilder.init(address(validator)).withDeadline(block.timestamp)
                .withValidationContract(address(validationContract))
        );
    }

    function testValid() public {
        snapStart("validate");
        validator.validateOrderInfo(OrderInfoBuilder.init(address(validator)));
        snapEnd();
    }

    function testValidationContractValid() public {
        MockValidationContract validationContract = new MockValidationContract();
        validationContract.setValid(true);
        validator.validateOrderInfo(
            OrderInfoBuilder.init(address(validator)).withValidationContract(
                address(validationContract)
            )
        );
    }
}
