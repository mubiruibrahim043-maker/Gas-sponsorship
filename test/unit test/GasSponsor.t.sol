// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {GasSponsor} from "../../src/GasSponsor.sol";

contract GasSponsorTest is Test {
    GasSponsor sponsor;

    address owner = address(1);

    address router = address(2);

    address relayer = address(3);

    function setUp() public {
        sponsor = new GasSponsor(owner);

        vm.prank(owner);

        sponsor.setRouter(router);

        vm.deal(owner, 10 ether);
    }

    function testReceiveETH() public {
        vm.prank(owner);

        (bool success,) = address(sponsor).call{value: 1 ether}("");

        assertTrue(success);

        assertEq(address(sponsor).balance, 1 ether);
    }

    function testReleaseGas() public {
        vm.prank(owner);

        sponsor.setMaxGasPerTransaction(0.5 ether);

        vm.prank(owner);

        (bool success,) = address(sponsor).call{value: 1 ether}("");

        assertTrue(success);

        uint256 beforeBalance = relayer.balance;

        vm.prank(router);

        sponsor.releaseGas(owner, relayer, 0.5 ether);

        assertEq(relayer.balance, beforeBalance + 0.5 ether);
    }

    function testOnlyRouterCanReleaseGas() public {
        vm.prank(owner);

        sponsor.setMaxGasPerTransaction(0.5 ether);

        vm.prank(owner);

        (bool success,) = address(sponsor).call{value: 1 ether}("");

        assertTrue(success);

        vm.prank(relayer);

        vm.expectRevert(GasSponsor.GasSponsor__OnlyRouter.selector);

        sponsor.releaseGas(owner, relayer, 0.5 ether);
    }

    function testCannotConstructWithZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));

        new GasSponsor(address(0));
    }

    function testSetRouter() public {
        address newRouter = address(10);

        vm.prank(owner);

        vm.expectEmit(true, true, false, false);
        emit GasSponsor.RouterUpdated(router, newRouter);

        sponsor.setRouter(newRouter);

        assertEq(sponsor.router(), newRouter);
    }

    function testCannotSetZeroRouter() public {
        vm.prank(owner);

        vm.expectRevert(GasSponsor.GasSponsor__ZeroAddress.selector);

        sponsor.setRouter(address(0));
    }

    function testReleaseGasRejectsZeroRelayer() public {
        vm.prank(owner);

        (bool success,) = address(sponsor).call{value: 1 ether}("");

        assertTrue(success);

        vm.prank(router);

        vm.expectRevert(GasSponsor.GasSponsor__ZeroAddress.selector);

        sponsor.releaseGas(owner, address(0), 0.5 ether);
    }

    function testReleaseGasRejectsZeroAmount() public {
        vm.prank(owner);

        (bool success,) = address(sponsor).call{value: 1 ether}("");

        assertTrue(success);

        vm.prank(router);

        vm.expectRevert(GasSponsor.GasSponsor__ZeroAmount.selector);

        sponsor.releaseGas(owner, relayer, 0);
    }

    function testReleaseGasRejectsInsufficientBalance() public {
        vm.prank(owner);

        sponsor.setMaxGasPerTransaction(2 ether);

        vm.prank(router);

        vm.expectRevert(GasSponsor.GasSponsor__InsufficientBalance.selector);

        sponsor.releaseGas(owner, relayer, 1 ether);
    }

    function testGetBalance() public {
        vm.prank(owner);

        (bool success,) = address(sponsor).call{value: 1 ether}("");

        assertTrue(success);

        assertEq(sponsor.getBalance(), 1 ether);
    }

    function testWithdraw() public {
        vm.prank(owner);

        (bool success,) = address(sponsor).call{value: 1 ether}("");

        assertTrue(success);

        uint256 ownerBalanceBefore = owner.balance;

        vm.prank(owner);

        sponsor.withdraw(0.5 ether);

        assertEq(owner.balance, ownerBalanceBefore + 0.5 ether);

        assertEq(sponsor.getBalance(), 0.5 ether);
    }

    function testWithdrawRejectsZeroAmount() public {
        vm.prank(owner);

        vm.expectRevert(GasSponsor.GasSponsor__ZeroAmount.selector);

        sponsor.withdraw(0);
    }

    function testWithdrawRejectsInsufficientBalance() public {
        vm.prank(owner);

        vm.expectRevert(GasSponsor.GasSponsor__InsufficientBalance.selector);

        sponsor.withdraw(1 ether);
    }

    function testOnlyOwnerCanWithdraw() public {
        vm.prank(relayer);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, relayer));

        sponsor.withdraw(1 ether);
    }

    function testSetMaxGasPerTransaction() public {
        uint256 maxAmount = 0.01 ether;

        vm.prank(owner);

        vm.expectEmit(false, false, false, true);
        emit GasSponsor.MaxGasPerTransactionUpdated(0, maxAmount);

        sponsor.setMaxGasPerTransaction(maxAmount);

        assertEq(sponsor.maxGasPerTransaction(), maxAmount);
    }

    function test_RevertWhen_SetMaxGasPerTransactionToZero() public {
        vm.prank(owner);

        vm.expectRevert(GasSponsor.GasSponsor__ZeroAmount.selector);

        sponsor.setMaxGasPerTransaction(0);
    }

    function test_RevertWhen_NonOwnerSetsMaxGasPerTransaction() public {
        vm.prank(relayer);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, relayer));

        sponsor.setMaxGasPerTransaction(0.01 ether);
    }

    function testReleaseGasAtMaxGasPerTransaction() public {
        uint256 maxAmount = 0.01 ether;

        vm.prank(owner);

        sponsor.setMaxGasPerTransaction(maxAmount);

        vm.deal(address(sponsor), 1 ether);

        uint256 relayerBalanceBefore = relayer.balance;

        vm.prank(router);

        sponsor.releaseGas(owner, relayer, maxAmount);

        assertEq(relayer.balance, relayerBalanceBefore + maxAmount);
    }

    function test_RevertWhen_ReleaseGasExceedsMaxGasPerTransaction() public {
        uint256 maxAmount = 0.01 ether;

        vm.prank(owner);

        sponsor.setMaxGasPerTransaction(maxAmount);

        vm.deal(address(sponsor), 10 ether);

        vm.prank(router);

        vm.expectRevert(GasSponsor.GasSponsor__ExceedsMaxGas.selector);

        sponsor.releaseGas(owner, relayer, 10 ether);
    }

    function testSecurityReportHashIsCorrect() public view {
        assertEq(sponsor.SECURITY_REPORT_HASH(), 0xa0800cada3cb23de6656c6edf01f8f1c66f802699c6cba55dab2cf0f8a23f255);
    }
}