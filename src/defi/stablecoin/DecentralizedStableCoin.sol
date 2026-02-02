// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/*
 * @title: DecentralizedStableCoin
 * Collateral: Exogenous (ETH & BTC)
 * Minting: Algorithmic
 * Relative Stability: Pegged to USD
 *
 * This is the contract meant to be governed by DSCEngine. This contract is just the ERC20 implementation of our stablecoin system.
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error Blacklisted(address _address);

    mapping(address => bool) public blacklist;

    constructor(address initialOwner) ERC20("DecentralizedStableCoin", "DSC") Ownable(initialOwner) {}

    function flagAddress(address _address, bool _flag) external onlyOwner {
        blacklist[_address] = _flag;
    }

    function mint(address _to, uint256 _amount) external onlyOwner {
        _mint(_to, _amount);
    }

    function burn(uint256 _amount) public override onlyOwner {
        super.burn(_amount);
    }

    function burnFrom(address account, uint256 amount) public override onlyOwner {
        super.burnFrom(account, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (blacklist[from] || blacklist[to]) {
            revert Blacklisted(blacklist[from] ? from : to);
        }
        super._update(from, to, value);
    }

    function decimals() public view virtual override returns (uint8) {
        return 8;
    }
}
