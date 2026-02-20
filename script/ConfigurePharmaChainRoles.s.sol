// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../src/Cannabis.sol";

contract ConfigurePharmaChainRoles is Script {
    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address proxy = vm.envAddress("PHARMA_PROXY");

        address production = vm.envOr("PRODUCTION_ADDR", address(0));
        address quality = vm.envOr("QUALITY_ADDR", address(0));
        address logistics = vm.envOr("LOGISTICS_ADDR", address(0));
        address oracle = vm.envOr("ORACLE_ADDR", address(0));

        PharmaChainERP pharma = PharmaChainERP(proxy);

        vm.startBroadcast(deployerPk);

        _grantIfProvided(pharma, pharma.PRODUCTION_ROLE(), production, "PRODUCTION_ROLE");
        _grantIfProvided(pharma, pharma.QUALITY_ROLE(), quality, "QUALITY_ROLE");
        _grantIfProvided(pharma, pharma.LOGISTICS_ROLE(), logistics, "LOGISTICS_ROLE");
        _grantIfProvided(pharma, pharma.ORACLE_ROLE(), oracle, "ORACLE_ROLE");

        vm.stopBroadcast();
    }

    function _grantIfProvided(
        PharmaChainERP pharma,
        bytes32 role,
        address account,
        string memory roleName
    ) internal {
        if (account == address(0)) {
            return;
        }

        if (pharma.hasRole(role, account)) {
            console2.log(roleName, "already granted to", account);
            return;
        }

        pharma.grantRole(role, account);
        console2.log("Granted", roleName, "to", account);
    }
}
