// SPDX-License-Identifier: LicenseRef-Gas-Sponsorship-Commercial-License
pragma solidity ^0.8.35;

import {GasSponsor} from "../../src/GasSponsor.sol";
import {GasSponsorRouter} from "../../src/GasSponsorRouter.sol";
import {SponsorRegistry} from "../../src/SponsorRegistry.sol";

interface Vm {
    function prank(address) external;
    function deal(address, uint256) external;

    function addr(uint256 privateKey) external returns (address);

    function sign(uint256 privateKey, bytes32 digest) external returns (uint8 v, bytes32 r, bytes32 s);
}

contract GasSponsorRouterFormalTarget {
    uint256 public value;

    fallback() external {
        value = 1;
    }
}

contract GasSponsorRouterFormal {
    GasSponsor internal sponsor;
    GasSponsorRouter internal router;
    SponsorRegistry internal registry;
    GasSponsorRouterFormalTarget internal target;

    uint256 internal constant USER_PRIVATE_KEY = 0x123456;
    address internal USER;
    address internal constant RELAYER = address(0x300);

    uint256 internal constant SPONSOR_AMOUNT = 0.01 ether;

    function setUp() public {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        USER = vm.addr(USER_PRIVATE_KEY);

        sponsor = new GasSponsor(address(this));

        registry = new SponsorRegistry(address(this));

        router = new GasSponsorRouter(address(registry));

        registry.registerSponsor(address(sponsor), address(sponsor), address(router));

        sponsor.setRouter(address(router));

        vm.deal(address(sponsor), 10 ether);

        target = new GasSponsorRouterFormalTarget();
    }

    function check_invalidNonceCannotExecute(uint256 invalidNonce) public {
        if (invalidNonce == 0) {
            return;
        }

        GasSponsorRouter.MetaTransaction memory metaTx = GasSponsorRouter.MetaTransaction({
            user: USER,
            target: address(target),
            sponsor: address(sponsor),
            data: "",
            nonce: invalidNonce,
            deadline: type(uint256).max,
            sponsorAmount: SPONSOR_AMOUNT
        });

        bytes memory signature = new bytes(0);

        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        vm.prank(RELAYER);

        (bool success,) =
            address(router).call(abi.encodeWithSelector(GasSponsorRouter.execute.selector, metaTx, signature));

        assert(!success);

        assert(router.nonces(USER) == 0);

        assert(target.value() == 0);
    }

    function check_expiredDeadlineCannotExecute(uint256 deadline) public {
        if (deadline >= block.timestamp) {
            return;
        }

        GasSponsorRouter.MetaTransaction memory metaTx = GasSponsorRouter.MetaTransaction({
            user: USER,
            target: address(target),
            sponsor: address(sponsor),
            data: "",
            nonce: 0,
            deadline: deadline,
            sponsorAmount: SPONSOR_AMOUNT
        });

        bytes memory signature = new bytes(0);

        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        vm.prank(RELAYER);

        (bool success,) =
            address(router).call(abi.encodeWithSelector(GasSponsorRouter.execute.selector, metaTx, signature));

        assert(!success);

        assert(router.nonces(USER) == 0);

        assert(target.value() == 0);
    }

    function check_invalidSignatureCannotExecute() public {
        GasSponsorRouter.MetaTransaction memory metaTx = GasSponsorRouter.MetaTransaction({
            user: USER,
            target: address(target),
            sponsor: address(sponsor),
            data: "",
            nonce: 0,
            deadline: type(uint256).max,
            sponsorAmount: SPONSOR_AMOUNT
        });

        bytes memory signature = new bytes(0);

        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        vm.prank(RELAYER);

        (bool success,) =
            address(router).call(abi.encodeWithSelector(GasSponsorRouter.execute.selector, metaTx, signature));

        assert(!success);

        assert(router.nonces(USER) == 0);

        assert(target.value() == 0);
    }

    function check_zeroSponsorAmountCannotExecute() public {
        GasSponsorRouter.MetaTransaction memory metaTx = GasSponsorRouter.MetaTransaction({
            user: USER,
            target: address(target),
            sponsor: address(sponsor),
            data: "",
            nonce: 0,
            deadline: type(uint256).max,
            sponsorAmount: 0
        });

        bytes memory signature = new bytes(0);

        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        vm.prank(RELAYER);

        (bool success,) =
            address(router).call(abi.encodeWithSelector(GasSponsorRouter.execute.selector, metaTx, signature));

        assert(!success);

        assert(router.nonces(USER) == 0);

        assert(target.value() == 0);
    }

    function check_unregisteredSponsorCannotExecute(address unregisteredSponsor) public {
        if (unregisteredSponsor == address(0)) {
            return;
        }

        if (unregisteredSponsor == address(sponsor)) {
            return;
        }

        GasSponsorRouter.MetaTransaction memory metaTx = GasSponsorRouter.MetaTransaction({
            user: USER,
            target: address(target),
            sponsor: unregisteredSponsor,
            data: "",
            nonce: 0,
            deadline: type(uint256).max,
            sponsorAmount: SPONSOR_AMOUNT
        });

        bytes memory signature = new bytes(0);

        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        vm.prank(RELAYER);

        (bool success,) =
            address(router).call(abi.encodeWithSelector(GasSponsorRouter.execute.selector, metaTx, signature));

        assert(!success);

        assert(router.nonces(USER) == 0);

        assert(target.value() == 0);
    }

    function check_wrongRegisteredRouterCannotExecute(address wrongRouter) public {
        if (wrongRouter == address(0)) {
            return;
        }

        if (wrongRouter == address(router)) {
            return;
        }

        registry.updateRouter(address(sponsor), wrongRouter);

        GasSponsorRouter.MetaTransaction memory metaTx = GasSponsorRouter.MetaTransaction({
            user: USER,
            target: address(target),
            sponsor: address(sponsor),
            data: "",
            nonce: 0,
            deadline: type(uint256).max,
            sponsorAmount: SPONSOR_AMOUNT
        });

        bytes memory signature = new bytes(0);

        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        vm.prank(RELAYER);

        (bool success,) =
            address(router).call(abi.encodeWithSelector(GasSponsorRouter.execute.selector, metaTx, signature));

        assert(!success);

        assert(router.nonces(USER) == 0);

        assert(target.value() == 0);
    }

    function check_successfulExecutionIncrementsNonce() public {
        GasSponsorRouter.MetaTransaction memory metaTx = GasSponsorRouter.MetaTransaction({
            user: USER,
            target: address(target),
            sponsor: address(sponsor),
            data: "",
            nonce: 0,
            deadline: type(uint256).max,
            sponsorAmount: SPONSOR_AMOUNT
        });

        bytes32 digest = router.getTypedDataHash(metaTx);

        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(USER_PRIVATE_KEY, digest);

        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(RELAYER);

        (bool success,) =
            address(router).call(abi.encodeWithSelector(GasSponsorRouter.execute.selector, metaTx, signature));

        assert(success);

        assert(router.nonces(USER) == 1);
    }
}
