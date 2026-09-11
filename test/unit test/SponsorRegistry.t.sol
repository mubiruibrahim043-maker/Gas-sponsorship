// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {SponsorRegistry} from "../../src/SponsorRegistry.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract SponsorRegistryTest is Test {
    SponsorRegistry registry;

    address owner = makeAddr("owner");
    address sponsor = makeAddr("sponsor");
    address gasSponsor = makeAddr("gasSponsor");
    address router = makeAddr("router");

    address newGasSponsor = makeAddr("newGasSponsor");
    address newRouter = makeAddr("newRouter");

    function setUp() public {
        registry = new SponsorRegistry(owner);
    }

    /*//////////////////////////////////////////////////////////////
                        REGISTER SPONSOR
    //////////////////////////////////////////////////////////////*/

    function testRegisterSponsor() public {
        vm.prank(owner);

        registry.registerSponsor(sponsor, gasSponsor, router);

        (address registeredGasSponsor, address registeredRouter, bool active) = registry.getSponsor(sponsor);

        assertEq(registeredGasSponsor, gasSponsor);

        assertEq(registeredRouter, router);

        assertTrue(active);

        assertTrue(registry.isRegistered(sponsor));
    }

    /*//////////////////////////////////////////////////////////////
                    REGISTER ZERO SPONSOR
    //////////////////////////////////////////////////////////////*/

    function testCannotRegisterZeroSponsor() public {
        vm.prank(owner);

        vm.expectRevert(SponsorRegistry.SponsorRegistry__ZeroAddress.selector);

        registry.registerSponsor(address(0), gasSponsor, router);
    }

    /*//////////////////////////////////////////////////////////////
                  REGISTER ZERO GAS SPONSOR
    //////////////////////////////////////////////////////////////*/

    function testCannotRegisterZeroGasSponsor() public {
        vm.prank(owner);

        vm.expectRevert(SponsorRegistry.SponsorRegistry__InvalidGasSponsor.selector);

        registry.registerSponsor(sponsor, address(0), router);
    }

    /*//////////////////////////////////////////////////////////////
                    REGISTER ZERO ROUTER
    //////////////////////////////////////////////////////////////*/

    function testCannotRegisterZeroRouter() public {
        vm.prank(owner);

        vm.expectRevert(SponsorRegistry.SponsorRegistry__InvalidRouter.selector);

        registry.registerSponsor(sponsor, gasSponsor, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                  REGISTER SAME SPONSOR TWICE
    //////////////////////////////////////////////////////////////*/

    function testCannotRegisterSponsorTwice() public {
        vm.startPrank(owner);

        registry.registerSponsor(sponsor, gasSponsor, router);

        vm.expectRevert(SponsorRegistry.SponsorRegistry__SponsorAlreadyRegistered.selector);

        registry.registerSponsor(sponsor, gasSponsor, router);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                         REMOVE SPONSOR
    //////////////////////////////////////////////////////////////*/

    function testRemoveSponsor() public {
        vm.startPrank(owner);

        registry.registerSponsor(sponsor, gasSponsor, router);

        registry.removeSponsor(sponsor);

        vm.stopPrank();

        assertFalse(registry.isRegistered(sponsor));

        (,, bool active) = registry.getSponsor(sponsor);

        assertFalse(active);
    }

    /*//////////////////////////////////////////////////////////////
                   REMOVE UNREGISTERED SPONSOR
    //////////////////////////////////////////////////////////////*/

    function testCannotRemoveUnregisteredSponsor() public {
        vm.prank(owner);

        vm.expectRevert(SponsorRegistry.SponsorRegistry__SponsorNotRegistered.selector);

        registry.removeSponsor(sponsor);
    }

    /*//////////////////////////////////////////////////////////////
                       UPDATE GAS SPONSOR
    //////////////////////////////////////////////////////////////*/

    function testUpdateGasSponsor() public {
        vm.startPrank(owner);

        registry.registerSponsor(sponsor, gasSponsor, router);

        registry.updateGasSponsor(sponsor, newGasSponsor);

        vm.stopPrank();

        (address registeredGasSponsor, address registeredRouter, bool active) = registry.getSponsor(sponsor);

        assertEq(registeredGasSponsor, newGasSponsor);

        assertEq(registeredRouter, router);

        assertTrue(active);
    }

    /*//////////////////////////////////////////////////////////////
                       UPDATE ROUTER
    //////////////////////////////////////////////////////////////*/

    function testUpdateRouter() public {
        vm.startPrank(owner);

        registry.registerSponsor(sponsor, gasSponsor, router);

        registry.updateRouter(sponsor, newRouter);

        vm.stopPrank();

        (address registeredGasSponsor, address registeredRouter, bool active) = registry.getSponsor(sponsor);

        assertEq(registeredGasSponsor, gasSponsor);

        assertEq(registeredRouter, newRouter);

        assertTrue(active);
    }

    /*//////////////////////////////////////////////////////////////
                    ONLY OWNER CAN REGISTER
    //////////////////////////////////////////////////////////////*/

    function testOnlyOwnerCanRegisterSponsor() public {
        vm.expectRevert();

        registry.registerSponsor(sponsor, gasSponsor, router);
    }

    /*//////////////////////////////////////////////////////////////
                     ONLY OWNER CAN REMOVE
    //////////////////////////////////////////////////////////////*/

    function testOnlyOwnerCanRemoveSponsor() public {
        vm.prank(owner);

        registry.registerSponsor(sponsor, gasSponsor, router);

        vm.expectRevert();

        registry.removeSponsor(sponsor);
    }

    /*//////////////////////////////////////////////////////////////
                    ONLY OWNER CAN UPDATE
    //////////////////////////////////////////////////////////////*/

    function testOnlyOwnerCanUpdateGasSponsor() public {
        vm.prank(owner);

        registry.registerSponsor(sponsor, gasSponsor, router);

        vm.expectRevert();

        registry.updateGasSponsor(sponsor, newGasSponsor);
    }

    function testOnlyOwnerCanUpdateRouter() public {
        vm.prank(owner);

        registry.registerSponsor(sponsor, gasSponsor, router);

        vm.expectRevert();

        registry.updateRouter(sponsor, newRouter);
    }

    /*//////////////////////////////////////////////////////////////
                         VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function testIsRegisteredReturnsFalseInitially() public {
        assertFalse(registry.isRegistered(sponsor));
    }

    function testGetSponsorReturnsCorrectData() public {
        vm.prank(owner);

        registry.registerSponsor(sponsor, gasSponsor, router);

        (address registeredGasSponsor, address registeredRouter, bool active) = registry.getSponsor(sponsor);

        assertEq(registeredGasSponsor, gasSponsor);

        assertEq(registeredRouter, router);

        assertTrue(active);
    }

    function testRemoveThenReregisterReplacesConfiguration() public {
        address oldGasSponsor = gasSponsor;
        address oldRouter = router;

        vm.startPrank(owner);

        registry.registerSponsor(sponsor, oldGasSponsor, oldRouter);

        registry.removeSponsor(sponsor);

        address replacementGasSponsor = makeAddr("replacementGasSponsor");
        address replacementRouter = makeAddr("replacementRouter");

        registry.registerSponsor(sponsor, replacementGasSponsor, replacementRouter);

        vm.stopPrank();

        (address registeredGasSponsor, address registeredRouter, bool active) = registry.getSponsor(sponsor);

        assertTrue(active);
        assertEq(registeredGasSponsor, replacementGasSponsor);
        assertEq(registeredRouter, replacementRouter);
    }

    /*//////////////////////////////////////////////////////////////
                  UPDATE GAS SPONSOR — INVALID CASES
    //////////////////////////////////////////////////////////////*/

    function testCannotUpdateGasSponsorForUnregisteredSponsor() public {
        vm.prank(owner);

        vm.expectRevert(SponsorRegistry.SponsorRegistry__SponsorNotRegistered.selector);

        registry.updateGasSponsor(sponsor, newGasSponsor);
    }

    function testCannotUpdateGasSponsorToZeroAddress() public {
        vm.startPrank(owner);

        registry.registerSponsor(sponsor, gasSponsor, router);

        vm.expectRevert(SponsorRegistry.SponsorRegistry__InvalidGasSponsor.selector);

        registry.updateGasSponsor(sponsor, address(0));

        vm.stopPrank();
    }

    function testCannotUpdateGasSponsorWithZeroSponsor() public {
        vm.prank(owner);

        vm.expectRevert(SponsorRegistry.SponsorRegistry__ZeroAddress.selector);

        registry.updateGasSponsor(address(0), newGasSponsor);
    }

    /*//////////////////////////////////////////////////////////////
                    UPDATE ROUTER — INVALID CASES
    //////////////////////////////////////////////////////////////*/

    function testCannotUpdateRouterToZeroAddress() public {
        vm.startPrank(owner);

        registry.registerSponsor(sponsor, gasSponsor, router);

        vm.expectRevert(SponsorRegistry.SponsorRegistry__InvalidRouter.selector);

        registry.updateRouter(sponsor, address(0));

        vm.stopPrank();
    }

    function testCannotUpdateRouterWithZeroSponsor() public {
        vm.prank(owner);

        vm.expectRevert(SponsorRegistry.SponsorRegistry__ZeroAddress.selector);

        registry.updateRouter(address(0), newRouter);
    }

    /*//////////////////////////////////////////////////////////////
                    CONSTRUCTOR INVALID CASE
    //////////////////////////////////////////////////////////////*/

    function testCannotDeployWithZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));

        new SponsorRegistry(address(0));
    }
}
