// SPDX-License-Identifier: LicenseRef-Gas-Sponsorship-Commercial-License
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";

import {MockTarget} from "../../src/MockTarget.sol";

contract MockTargetTest is Test {
    MockTarget target;

    address forwarder = address(100);

    address user = address(200);

    function setUp() public {
        target = new MockTarget(forwarder);
    }

    function testSetValue() public {
        vm.prank(user);

        target.setValue(100);

        assertEq(target.value(), 100);

        assertEq(target.lastUser(), user);
    }

    function testCannotSetZero() public {
        vm.expectRevert(MockTarget.MockTarget__ZeroValue.selector);

        target.setValue(0);
    }
}
