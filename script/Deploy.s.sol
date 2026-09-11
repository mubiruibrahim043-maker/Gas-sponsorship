// SPDX-License-Identifier: LicenseRef-Gas-Sponsorship-Commercial-License
pragma solidity ^0.8.35;
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {SponsorRegistry} from "../src/SponsorRegistry.sol";
import {GasSponsor} from "../src/GasSponsor.sol";
import {GasSponsorRouter} from "../src/GasSponsorRouter.sol";
import {MockTarget} from "../src/MockTarget.sol";

contract Deploy is Script {
    /*//////////////////////////////////////////////////////////////
                                  CONTRACTS
        ////////////////////

    //////////////////////////////////////////*/

    SponsorRegistry public registry;
    GasSponsor public gasSponsor;
    GasSponsorRouter public router;
    MockTarget public target;

    /*//////////////////////////////////////////////////////////////
                              ADDRESSES
    //////////////////////////////////////////////////////////////*/

    address public owner;
    address public sponsor;

    /*//////////////////////////////////////////////////////////////
                                RUN
    //////////////////////////////////////////////////////////////*/

    function run() external returns (SponsorRegistry, GasSponsor, GasSponsorRouter, MockTarget) {
        /*
         * Load the deployer's private key.
         */
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        /*
         * The deployer becomes the owner.
         */
        owner = vm.addr(deployerPrivateKey);

        /*
         * In the final system, sponsor represents the
         * sponsor identity registered in the Registry.
         *
         * For the first deployment we use the owner address.
         *
         * You can later replace this with a dedicated
         * sponsor address.
         */
        sponsor = owner;

        /*
         * Start broadcasting transactions.
         */
        vm.startBroadcast(deployerPrivateKey);

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
         */

        gasSponsor = new GasSponsor(owner);

        /*
         * ---------------------------------------------------------
         * 3. Deploy GasSponsorRouter
         * ---------------------------------------------------------
         *
         * Router needs to know where the Registry is.
         */

        router = new GasSponsorRouter(address(registry));

        /*
         * ---------------------------------------------------------
         * 4. Deploy target
         * ---------------------------------------------------------
         *
         * This is only a test/demo target.
         * Your real system can interact with any target.
         */

        target = new MockTarget(address(router));

        /*
         * ---------------------------------------------------------
         * 5. Connect GasSponsor -> Router
         * ---------------------------------------------------------
         */

        gasSponsor.setRouter(address(router));

        /*
         * ---------------------------------------------------------
         * 6. Register sponsor
         * ---------------------------------------------------------
         *
         * Registry records:
         *
         * sponsor
         *     ↓
         * GasSponsor
         *     ↓
         * Router
         */

        registry.registerSponsor(sponsor, address(gasSponsor), address(router));

        /*
         * Stop broadcasting.
         */
        vm.stopBroadcast();

        /*
         * Print deployed addresses.
         */
        console2.log("SponsorRegistry:", address(registry));

        console2.log("GasSponsor:", address(gasSponsor));

        console2.log("GasSponsorRouter:", address(router));

        console2.log("MockTarget:", address(target));

        console2.log("Owner:", owner);

        console2.log("Sponsor:", sponsor);

        return (registry, gasSponsor, router, target);
    }
}
