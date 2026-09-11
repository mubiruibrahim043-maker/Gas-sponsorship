// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";

import {SponsorRegistry} from "../../../src/SponsorRegistry.sol";
import {GasSponsor} from "../../../src/GasSponsor.sol";
import {GasSponsorRouter} from "../../../src/GasSponsorRouter.sol";

contract IntegrationTarget {
    uint256 private s_value;
    address private s_user;

    event ValueChanged(address indexed user, uint256 indexed oldValue, uint256 indexed newValue);

    function setValue(uint256 newValue) external {
        address user;

        assembly {
            user := shr(96, calldataload(sub(calldatasize(), 20)))
        }

        uint256 oldValue = s_value;

        s_value = newValue;
        s_user = user;

        emit ValueChanged(user, oldValue, newValue);
    }

    function getValue() external view returns (uint256) {
        return s_value;
    }

    function getUser() external view returns (address) {
        return s_user;
    }
}

contract GasSponsorSystemIntegrationTest is Test {
    /*//////////////////////////////////////////////////////////////
                              CONTRACTS
    //////////////////////////////////////////////////////////////*/

    SponsorRegistry registry;
    GasSponsor gasSponsor;
    GasSponsorRouter router;
    IntegrationTarget target;

    /*//////////////////////////////////////////////////////////////
                              ACCOUNTS
    //////////////////////////////////////////////////////////////*/

    address owner = makeAddr("owner");
    address sponsor = makeAddr("sponsor");
    address relayer = makeAddr("relayer");

    address user;

    uint256 userPrivateKey = 12345;

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 constant SPONSOR_AMOUNT = 0.01 ether;

    /*//////////////////////////////////////////////////////////////
                              SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        /*
         * Create the user from a private key.
         */

        user = vm.addr(userPrivateKey);

        /*
         * Give the owner ETH.
         */

        vm.deal(owner, 10 ether);

        /*
         * Give the relayer ETH.
         */

        vm.deal(relayer, 10 ether);

        /*
         * ---------------------------------------------------------
         * 1. Deploy SponsorRegistry
         * ---------------------------------------------------------
         */

        registry = new SponsorRegistry(owner);

        /*
         * ---------------------------------------------------------
         * 2. Deploy GasSponsor
         * ---------------------------------------------------------
         *
         * Owner owns the GasSponsor.
         */

        vm.prank(owner);

        gasSponsor = new GasSponsor(owner);

        /*
         * ---------------------------------------------------------
         * 3. Deploy Router
         * ---------------------------------------------------------
         *
         * Router receives Registry address.
         */

        router = new GasSponsorRouter(address(registry));

        /*
         * ---------------------------------------------------------
         * 4. Deploy Target
         * ---------------------------------------------------------
         */

        target = new IntegrationTarget();

        /*
         * ---------------------------------------------------------
         * 5. Register sponsor
         * ---------------------------------------------------------
         *
         * Registry connects:
         *
         * sponsor
         *    ↓
         * GasSponsor
         *    ↓
         * Router
         */

        vm.prank(owner);

        registry.registerSponsor(sponsor, address(gasSponsor), address(router));

        /*
         * ---------------------------------------------------------
         * 6. Connect GasSponsor to Router
         * ---------------------------------------------------------
         */

        vm.prank(owner);

        gasSponsor.setRouter(address(router));

        /*
         * Set maximum gas allowed per transaction.
         */

        vm.prank(owner);

        gasSponsor.setMaxGasPerTransaction(100 ether);
        /*
        * ---------------------------------------------------------
        * 7. Fund GasSponsor
        * ---------------------------------------------------------
        */

        vm.deal(address(gasSponsor), 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                    FULL SYSTEM SUCCESS FLOW
    //////////////////////////////////////////////////////////////*/

    function testFullGasSponsorshipFlow() public {
        /*
         * Target function we want to execute.
         */

        bytes memory data = abi.encodeWithSelector(IntegrationTarget.setValue.selector, uint256(123));

        /*
         * Get current user nonce.
         */

        uint256 nonce = router.getNonce(user);

        /*
         * Create MetaTransaction.
         */

        GasSponsorRouter.MetaTransaction memory metaTx = GasSponsorRouter.MetaTransaction({
            user: user,
            target: address(target),
            sponsor: sponsor,
            data: data,
            nonce: nonce,
            deadline: block.timestamp + 1 hours,
            sponsorAmount: SPONSOR_AMOUNT
        });

        /*
         * Get EIP-712 digest.
         */

        bytes32 digest = router.getTypedDataHash(metaTx);

        /*
         * User signs the digest.
         */

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        bytes memory signature = abi.encodePacked(r, s, v);

        /*
         * Record balances before execution.
         */

        uint256 relayerBalanceBefore = relayer.balance;

        uint256 sponsorBalanceBefore = address(gasSponsor).balance;

        /*
         * Target should initially be zero.
         */

        assertEq(target.getValue(), 0);

        /*
         * Execute meta-transaction.
         */

        vm.prank(relayer);

        router.execute(metaTx, signature);

        /*
         * Target value should be updated.
         */

        assertEq(target.getValue(), 123);

        /*
         * Target should identify the original user.
         */

        assertEq(target.getUser(), user);

        /*
         * Nonce should increase.
         */

        assertEq(router.getNonce(user), nonce + 1);

        /*
         * Relayer should receive the sponsorship amount.
         */

        assertEq(relayer.balance, relayerBalanceBefore + SPONSOR_AMOUNT);

        /*
         * GasSponsor balance should decrease
         * by the sponsorship amount.
         */

        assertEq(address(gasSponsor).balance, sponsorBalanceBefore - SPONSOR_AMOUNT);
    }
}

