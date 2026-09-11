// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {SponsorRegistry} from "../../../src/SponsorRegistry.sol";

contract SponsorRegistryFuzzTest is Test {
    SponsorRegistry public registry;

    address public owner = address(this);

    uint256 public constant USER_PRIVATE_KEY = 1;

    address public sponsor;
    address public gasSponsor;
    address public router;

    function setUp() public {
        sponsor = vm.addr(USER_PRIVATE_KEY);

        gasSponsor = address(0x1001);
        router = address(0x2001);

        registry = new SponsorRegistry(owner);
    }

    /*//////////////////////////////////////////////////////////////
                    FUZZ: REGISTER SPONSOR
    //////////////////////////////////////////////////////////////*/

    function testFuzzRegisterSponsor(address fuzzSponsor, address fuzzGasSponsor, address fuzzRouter) public {
        vm.assume(fuzzSponsor != address(0));
        vm.assume(fuzzGasSponsor != address(0));
        vm.assume(fuzzRouter != address(0));

        registry.registerSponsor(fuzzSponsor, fuzzGasSponsor, fuzzRouter);

        (address registeredGasSponsor, address registeredRouter, bool active) = registry.getSponsor(fuzzSponsor);

        assertEq(registeredGasSponsor, fuzzGasSponsor);

        assertEq(registeredRouter, fuzzRouter);

        assertTrue(active);

        assertTrue(registry.isRegistered(fuzzSponsor));
    }

    /*//////////////////////////////////////////////////////////////
                    FUZZ: ZERO SPONSOR
    //////////////////////////////////////////////////////////////*/

    function testFuzzRejectsZeroSponsor(address fuzzGasSponsor, address fuzzRouter) public {
        vm.assume(fuzzGasSponsor != address(0));
        vm.assume(fuzzRouter != address(0));

        vm.expectRevert(SponsorRegistry.SponsorRegistry__ZeroAddress.selector);

        registry.registerSponsor(address(0), fuzzGasSponsor, fuzzRouter);
    }

    /*//////////////////////////////////////////////////////////////
                    FUZZ: ZERO GAS SPONSOR
    //////////////////////////////////////////////////////////////*/

    function testFuzzRejectsZeroGasSponsor(address fuzzSponsor, address fuzzRouter) public {
        vm.assume(fuzzSponsor != address(0));
        vm.assume(fuzzRouter != address(0));

        vm.expectRevert(SponsorRegistry.SponsorRegistry__InvalidGasSponsor.selector);

        registry.registerSponsor(fuzzSponsor, address(0), fuzzRouter);
    }

    /*//////////////////////////////////////////////////////////////
                    FUZZ: ZERO ROUTER
    //////////////////////////////////////////////////////////////*/

    function testFuzzRejectsZeroRouter(address fuzzSponsor, address fuzzGasSponsor) public {
        vm.assume(fuzzSponsor != address(0));
        vm.assume(fuzzGasSponsor != address(0));

        vm.expectRevert(SponsorRegistry.SponsorRegistry__InvalidRouter.selector);

        registry.registerSponsor(fuzzSponsor, fuzzGasSponsor, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                    FUZZ: CANNOT REGISTER TWICE
    //////////////////////////////////////////////////////////////*/

    function testFuzzRejectsDuplicateRegistration(address fuzzGasSponsor, address fuzzRouter) public {
        vm.assume(fuzzGasSponsor != address(0));
        vm.assume(fuzzRouter != address(0));

        registry.registerSponsor(sponsor, fuzzGasSponsor, fuzzRouter);

        vm.expectRevert(SponsorRegistry.SponsorRegistry__SponsorAlreadyRegistered.selector);

        registry.registerSponsor(sponsor, fuzzGasSponsor, fuzzRouter);
    }

    /*//////////////////////////////////////////////////////////////
                    FUZZ: REMOVE SPONSOR
    //////////////////////////////////////////////////////////////*/

    function testFuzzRemoveSponsor(address fuzzGasSponsor, address fuzzRouter) public {
        vm.assume(fuzzGasSponsor != address(0));
        vm.assume(fuzzRouter != address(0));

        registry.registerSponsor(sponsor, fuzzGasSponsor, fuzzRouter);

        registry.removeSponsor(sponsor);

        assertFalse(registry.isRegistered(sponsor));

        (,, bool active) = registry.getSponsor(sponsor);

        assertFalse(active);
    }

    /*//////////////////////////////////////////////////////////////
                    FUZZ: REMOVE UNREGISTERED
    //////////////////////////////////////////////////////////////*/

    function testFuzzRejectsRemoveUnregistered(address fuzzSponsor) public {
        vm.assume(fuzzSponsor != address(0));

        vm.expectRevert(SponsorRegistry.SponsorRegistry__SponsorNotRegistered.selector);

        registry.removeSponsor(fuzzSponsor);
    }

    /*//////////////////////////////////////////////////////////////
                    FUZZ: UPDATE GAS SPONSOR
    //////////////////////////////////////////////////////////////*/

    function testFuzzUpdateGasSponsor(address fuzzGasSponsor, address newGasSponsor, address fuzzRouter) public {
        vm.assume(fuzzGasSponsor != address(0));
        vm.assume(newGasSponsor != address(0));
        vm.assume(fuzzRouter != address(0));

        registry.registerSponsor(sponsor, fuzzGasSponsor, fuzzRouter);

        registry.updateGasSponsor(sponsor, newGasSponsor);

        assertEq(registry.getGasSponsor(sponsor), newGasSponsor);
    }

    /*//////////////////////////////////////////////////////////////
                    FUZZ: UPDATE ROUTER
    //////////////////////////////////////////////////////////////*/

    function testFuzzUpdateRouter(address fuzzGasSponsor, address fuzzRouter, address newRouter) public {
        vm.assume(fuzzGasSponsor != address(0));
        vm.assume(fuzzRouter != address(0));
        vm.assume(newRouter != address(0));

        registry.registerSponsor(sponsor, fuzzGasSponsor, fuzzRouter);

        registry.updateRouter(sponsor, newRouter);

        assertEq(registry.getRouter(sponsor), newRouter);
    }

    /*//////////////////////////////////////////////////////////////
                    FUZZ: ONLY OWNER CAN REGISTER
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyOwnerCanRegister(
        address caller,
        address fuzzSponsor,
        address fuzzGasSponsor,
        address fuzzRouter
    ) public {
        vm.assume(caller != owner);
        vm.assume(fuzzSponsor != address(0));
        vm.assume(fuzzGasSponsor != address(0));
        vm.assume(fuzzRouter != address(0));

        vm.prank(caller);

        vm.expectRevert();

        registry.registerSponsor(fuzzSponsor, fuzzGasSponsor, fuzzRouter);
    }

    /*//////////////////////////////////////////////////////////////
                    FUZZ: ONLY OWNER CAN REMOVE
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyOwnerCanRemove(address caller) public {
        vm.assume(caller != owner);
        vm.assume(caller != address(0));

        registry.registerSponsor(sponsor, gasSponsor, router);

        vm.prank(caller);

        vm.expectRevert();

        registry.removeSponsor(sponsor);
    }

    /*//////////////////////////////////////////////////////////////
                    FUZZ: ONLY OWNER CAN UPDATE GAS SPONSOR
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyOwnerCanUpdateGasSponsor(address caller, address newGasSponsor) public {
        vm.assume(caller != owner);
        vm.assume(caller != address(0));
        vm.assume(newGasSponsor != address(0));

        registry.registerSponsor(sponsor, gasSponsor, router);

        vm.prank(caller);

        vm.expectRevert();

        registry.updateGasSponsor(sponsor, newGasSponsor);
    }

    /*//////////////////////////////////////////////////////////////
                    FUZZ: ONLY OWNER CAN UPDATE ROUTER
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyOwnerCanUpdateRouter(address caller, address newRouter) public {
        vm.assume(caller != owner);
        vm.assume(caller != address(0));
        vm.assume(newRouter != address(0));

        registry.registerSponsor(sponsor, gasSponsor, router);

        vm.prank(caller);

        vm.expectRevert();

        registry.updateRouter(sponsor, newRouter);
    }
}
