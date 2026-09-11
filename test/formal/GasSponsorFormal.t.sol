// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {GasSponsor} from "../../src/GasSponsor.sol";

interface Vm {
    function prank(address) external;
    function deal(address, uint256) external;
}

contract GasSponsorFormal {
    GasSponsor internal sponsor;

    address internal constant OWNER = address(0x100);

    address internal constant ROUTER = address(0x200);

    function setUp() public {
        sponsor = new GasSponsor(OWNER);

        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        vm.prank(OWNER);

        sponsor.setRouter(ROUTER);

        vm.deal(address(sponsor), 10 ether);

        vm.prank(OWNER);

        sponsor.setMaxGasPerTransaction(10 ether);

        vm.prank(OWNER);

        sponsor.setUserAuthorization(OWNER, true);
    }

    function check_onlyRouterCanReleaseGas(address attacker, address relayer, uint256 amount) public {
        if (attacker == ROUTER) {
            return;
        }

        if (relayer == address(0)) {
            return;
        }

        if (amount == 0 || amount > 10 ether) {
            return;
        }

        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        vm.prank(attacker);

        (bool success,) = address(sponsor).call(abi.encodeCall(GasSponsor.releaseGas, (attacker, relayer, amount)));

        assert(!success);
    }

    function check_releaseGasCannotExceedBalance(address relayer, uint256 balance, uint256 amount) public {
        if (relayer == address(0)) {
            return;
        }

        if (balance > 10 ether) {
            return;
        }

        if (amount == 0) {
            return;
        }

        if (amount <= balance) {
            return;
        }

        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        vm.deal(address(sponsor), balance);

        vm.prank(ROUTER);

        (bool success,) = address(sponsor).call(abi.encodeCall(GasSponsor.releaseGas, (OWNER, relayer, amount)));

        assert(!success);
    }

    function check_onlyOwnerCanWithdraw(address attacker, uint256 amount) public {
        if (attacker == OWNER) {
            return;
        }

        if (amount == 0 || amount > 10 ether) {
            return;
        }

        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        vm.deal(address(sponsor), 10 ether);

        vm.prank(attacker);

        (bool success,) = address(sponsor).call(abi.encodeCall(GasSponsor.withdraw, (amount)));

        assert(!success);
    }
}
