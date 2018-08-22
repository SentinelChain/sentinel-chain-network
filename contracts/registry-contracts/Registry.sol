pragma solidity ^0.4.23;

import "zeppelin-solidity/contracts/ownership/Ownable.sol";
import './Livestock.sol';

contract Registry is Ownable {
    
    struct Implementer {
        address implementer;
        bytes multichain;
        bool verified;
        bool removing;
    }

    mapping (address => address) managers;
    mapping (bytes28 => Livestock) livestockMap;
    mapping (bytes32 => address) registeredLivestock;
    mapping (bytes => bool) registeredMultichain;
    mapping (address => mapping(bytes32 => Implementer)) interfacesMap;

    modifier canManage(address addr) {
        require(getManager(addr) == msg.sender);
        _;
    }
    
    event LivestockAdded(string name, address indexed addr);
    event LivestockRemoved(string name, address indexed addr);
    event InterfaceImplementerSet(
        address indexed addr, 
        bytes32 indexed interfaceHash, 
        string indexed multichain);
    event InterfaceImplementerRemoving(
        address indexed addr, 
        bytes32 indexed interfaceHash);
    event InterfaceImplementerVerified(
        address indexed addr, 
        bytes32 indexed interfaceHash,
        string action);
    event ManagerChanged(address indexed addr, address indexed newManager);

    /// @notice Query the combined interface given a name and id 
    /// @param interfaceName Name of the interfce
    function interfaceHash(string interfaceName, uint id) 
        public pure returns(bytes32) 
    {
        bytes32 interfaceBytes;
        bytes32 idBytes = bytes32(id);
        assembly {
            interfaceBytes := mload(add(interfaceName, 32))
        }
        if (bytes(interfaceName).length > 28 || idBytes > 0xffffffff) {
            return 0;
        }
        return interfaceBytes | idBytes;
    }

    /// @notice GetManager
    function getManager(address addr) public view returns(address) {
        // By default the manager of an address is the same address
        if (managers[addr] == 0) {
            return addr;
        } else {
            return managers[addr];
        }
    }

    function setManager(address addr, address newManager) 
        external canManage(addr) 
    {
        managers[addr] = newManager == addr ? 0 : newManager;
        emit ManagerChanged(addr, newManager);
    }
    
    function getLivestock(string _name) external view returns(address) {
        bytes28 name = toBytes28(_name);
        return livestockMap[name];
    }
     
    function setLivestock(Livestock _livestock) external onlyOwner {
        bytes28 name = toBytes28(_livestock.symbol());
        require(_livestock.owner() == address(this), "The livestock contract must have this Registry contract as owner");
        require(livestockMap[name] == address(0), "This livestock is already set");
        livestockMap[name] = _livestock;
        emit LivestockAdded(_livestock.symbol(), _livestock);
    }
    
    function removeCurrency(string _name) external onlyOwner {
        bytes28 name = toBytes28(_name);
        Livestock livestock = livestockMap[name];
        require(livestock != address(0), "This livestock hasn't been set");
        livestock.transferOwnership(msg.sender);
        livestockMap[name] = Livestock(0);
        emit LivestockRemoved(_name, livestock);
    }
    
    function getInterfaceImplementer(address addr, bytes32 iHash) public 
        view returns (address implementer, string multichain, bool verified) 
    {
        Implementer memory interfaces = getInterfaces(addr, iHash);
        implementer = interfaces.implementer;
        multichain = string(interfaces.multichain);
        verified = interfaces.verified;
    }

    function setInterfaceImplementer(
        address addr, bytes32 iHash, string multichain) 
        external canManage(addr) 
    {
        Implementer memory interfaces = interfacesMap[addr][iHash];
        bytes memory multichainBytes = bytes(multichain);
        require(multichainBytes.length == 38);
        require(!registeredMultichain[multichainBytes]);
        require(!interfaces.verified);
        if (iHash == "attestator") {
            require(!interfacesMap[addr]["user"].verified);
        } else {
            require(!interfacesMap[addr]["attestator"].verified);
            uint id = uint(bytes4(iHash << (8 * 28)));
            bytes28 name = bytes28(iHash);
            if (id > 0) {
                require(interfacesMap[addr]["user"].verified);
                require(!livestockMap[name].exists(id));
            }
        }
        if (registeredMultichain[interfaces.multichain]) {
            registeredMultichain[interfaces.multichain] = false;
        }
        interfacesMap[addr][iHash].implementer = msg.sender;
        interfacesMap[addr][iHash].multichain = multichainBytes;
        emit InterfaceImplementerSet(addr, iHash, multichain);
    }
    
    function verifyInterfaceImplementer(address addr, bytes32 iHash) external {
        Implementer memory interfaces = interfacesMap[addr][iHash];
        require(interfaces.implementer != 0);
        require(!interfaces.verified);
        require(!registeredMultichain[interfaces.multichain]);
        if (iHash == "attestator") {
            require(msg.sender == owner);
            require(!interfacesMap[addr]["user"].verified);
        } else {
            require(interfacesMap[msg.sender]["attestator"].verified);
            require(!interfacesMap[addr]["attestator"].verified);
            uint id = uint(bytes4(iHash << (8 * 28)));
            bytes28 name = bytes28(iHash);
            if (id > 0) {
                livestockMap[name].mint(addr, id);
                registeredLivestock[iHash] = addr;
            }
        }
        registeredMultichain[interfaces.multichain] = true;
        interfacesMap[addr][iHash].verified = true;
        emit InterfaceImplementerVerified(addr, iHash, "Added");
    }
    
    function removeInterfaceImplementer(address addr, bytes32 iHash) 
        external canManage(addr) 
    {
        Implementer memory interfaces = getInterfaces(addr, iHash);
        require(interfaces.verified);
        interfacesMap[addr][iHash].removing = true;
        emit InterfaceImplementerRemoving(addr, iHash);
    }
    
    function verifyInterfaceRemoval(address addr, bytes32 iHash) external {
        Implementer memory interfaces = interfacesMap[addr][iHash];
        Implementer memory empty = Implementer(0x0, "", false, false);
        require(interfaces.removing);
        require(interfacesMap[msg.sender]["attestator"].verified);
        uint id = uint(bytes4(iHash << (8 * 28)));
        bytes28 name = bytes28(iHash);
        if (id > 0) {
            address registered = registeredLivestock[iHash];
            registeredLivestock[iHash] = 0;
            livestockMap[name].burn(addr, id);
            interfacesMap[addr][iHash].removing = false;
            interfacesMap[registered][iHash] = empty;
        } else {
            interfacesMap[addr][iHash] = empty;
        }
        registeredMultichain[interfaces.multichain] = false;
        emit InterfaceImplementerVerified(addr, iHash, "Removed");
    }
    
    function toBytes28(string name) internal pure returns(bytes28 result) {
        assembly {
            result := mload(add(name, 32))
        }
    }
    
    function getInterfaces(address addr, bytes32 iHash) 
        internal view returns(Implementer interfaces) 
    {
        uint id = uint(bytes4(iHash << (8 * 28)));
        bytes28 name = bytes28(iHash);
        address registered = registeredLivestock[iHash];
        if (address(livestockMap[name]) != 0 && 
            livestockMap[name].exists(id)) {
            if (livestockMap[name].ownerOf(id) == addr) {
                interfaces = interfacesMap[registered][iHash];
            } else {
                interfaces = interfacesMap[addr][0x0];
            }
        } else {
            interfaces = interfacesMap[addr][iHash];
        }
    }
}