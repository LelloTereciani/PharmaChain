// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/Cannabis.sol";

contract DeployPharmaChain is Script {
    function run() external returns (address implementation, address proxy, PharmaChainERP pharma) {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        string memory baseUri = vm.envOr("BASE_URI", string("ipfs://pharma/{id}.json"));

        vm.startBroadcast(deployerPk);

        implementation = address(new PharmaChainERP());
        bytes memory initData = abi.encodeCall(PharmaChainERP.initialize, (baseUri));
        proxy = address(new ERC1967Proxy(implementation, initData));

        vm.stopBroadcast();

        pharma = PharmaChainERP(proxy);

        console2.log("PharmaChainERP implementation:", implementation);
        console2.log("PharmaChainERP proxy:", proxy);
    }
}
