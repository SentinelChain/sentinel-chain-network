pragma solidity 0.4.24;


import "./BasicBridge.sol";
import "../../shared/ERC677/IBurnableMintableERC677Token.sol";
import "../../shared/IWhitelist.sol";
import "./Whitelistable.sol";

contract ERC677Bridge is BasicBridge, Whitelistable {
    function erc677token() public view returns(IBurnableMintableERC677Token) {
        return IBurnableMintableERC677Token(
            addressStorage[keccak256(abi.encodePacked("erc677token"))]
        );
    }

    function setErc677token(address _token) internal {
        require(_token != address(0) && isContract(_token));
        addressStorage[keccak256(abi.encodePacked("erc677token"))] = _token;
    }

    function onTokenTransfer(address _from, uint256 _value, bytes /*_data*/)
        external
        returns(bool)
    {
        require(msg.sender == address(erc677token()));
        uint256 valueToTransfer;
        if (_from == tollAddress()) {
            valueToTransfer = _value;
        } else {
            require(_isWhitelisted(_from));
            require(_value > tollFee());
            valueToTransfer = _value - tollFee();
            require(withinLimit(_value));
            setTotalSpentPerDay(
                getCurrentDay(),
                totalSpentPerDay(getCurrentDay()).add(_value)
            );
            erc677token().transfer(tollAddress(), tollFee());
        }
        erc677token().burn(valueToTransfer);
        fireEventOnTokenTransfer(_from, valueToTransfer);
        return true;
    }

    function fireEventOnTokenTransfer(address /*_from */, uint256 /* _value */)
        internal
    {
        // has to be defined
    }

}
