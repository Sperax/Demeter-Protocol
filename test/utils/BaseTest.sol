pragma solidity >=0.6.2 <0.9.0;
pragma experimental ABIEncoderV2;
import { Test } from "forge-std/Test.sol";
import { BaseFarm } from "../../contracts/BaseFarm.sol";
import { FarmFactory } from "../../contracts/FarmFactory.sol";
import { BaseFarmDeployer } from "../../contracts/BaseFarmDeployer.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

abstract contract Setup is Test {
  // Define global constants | Test config
  // @dev Make it 0 to test on latest
  uint256 public constant FORK_BLOCK = 140358112; //TODO :
  uint256 public constant NUM_ACTORS = 2;
  uint256 public constant MIN_BALANCE = 1000000000000000000;
  uint256 public constant GAS_LIMIT = 1000000000;
  uint256 public constant NO_LOCKUP_REWARD_RATE = 1e18;
  uint256 public constant LOCKUP_REWARD_RATE = 2e18;
  uint256 public constant COOLDOWN_PERIOD =21;

  address public constant SPA = 0x5575552988A3A80504bBaeB1311674fCFd40aD4B;
  address public constant USDS = 0xD74f5255D557944cf7Dd0E45FF521520002D5748;
  address public constant USDCe = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
  address public constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
  address public constant FRAX = 0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F;
  address public constant VST = 0x64343594Ab9b56e99087BfA6F2335Db24c2d1F17;
  address public constant L2DAO = 0x2CaB3abfC1670D1a452dF502e216a66883cDf079;
  address public constant DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
  bytes32 public constant NO_LOCK_DATA =0x0000000000000000000000000000000000000000000000000000000000000000;
  bytes32 public constant LOCK_DATA =0x0000000000000000000000000000000000000000000000000000000000000001;

  // Define Demeter constants here
  address internal PROXY_OWNER;
  address internal USDS_OWNER;
  address internal PROXY_ADMIN;
  address internal OWNER;
  address internal DEMETER_FACTORY;
  address internal BALANCER_VAULT;
  address internal USDS_VAULT;

  // Define fork networks
  uint256 internal arbFork;

  address[] public actors;
  address internal currentActor;

  /// @notice Get a pre-set address for prank
  /// @param actorIndex Index of the actor
  modifier useActor(uint256 actorIndex) {
    currentActor = actors[bound(actorIndex, 0, actors.length - 1)];
    vm.startPrank(currentActor);
    _;
    vm.stopPrank();
  }

  /// @notice Start a prank session with a known user addr
  modifier useKnownActor(address user) {
    currentActor = user;
    vm.startPrank(currentActor);
    _;
    vm.stopPrank();
  }

  /// @notice Initialize global test configuration.
  function setUp() public virtual {
    /// @dev Initialize actors for testing.
    string memory mnemonic = vm.envString("TEST_MNEMONIC");
    for (uint32 i = 0; i < NUM_ACTORS; ++i) {
      (address act, ) = deriveRememberKey(mnemonic, i);
      actors.push(act);
    }
  }

  /// @notice
  function setArbitrumFork() public {
    string memory arbRpcUrl = vm.envString("ARB_URL");
    arbFork = vm.createFork(arbRpcUrl);
    vm.selectFork(arbFork);
    if (FORK_BLOCK != 0) vm.rollFork(FORK_BLOCK);
  }
}

abstract contract BaseTest is Setup {
  function setUp() public virtual override {
    super.setUp();
    PROXY_ADMIN = 0x3E49925A79CbFb68BAa5bc9DFb4f7D955D1ddF25;
    OWNER = 0x432c3BcdF5E26Ec010dF9C1ddf8603bbe261c188;
    USDS_OWNER = 0x5b12d9846F8612E439730d18E1C12634753B1bF1;
    PROXY_OWNER = 0x6d5240f086637fb408c7F727010A10cf57D51B62;
    DEMETER_FACTORY = 0xC4fb09E0CD212367642974F6bA81D8e23780A659;
    BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    USDS_VAULT = 0xF783DD830A4650D2A8594423F123250652340E3f;
  }
}
