pragma solidity 0.4.24;

// TODO: Create connection deadline. Deposit goes to user who made it further in the game
// TODO: moveTimeline should be measured in blocks
contract Ultimatum { 
  using SafeMath for uint; 
  // ------------------------------------------------------------------------
  //  Boolean storage representing pairing requests and connections
  // ------------------------------------------------------------------------
  mapping (bytes32 => bool) public requested;
  mapping (bytes32 => bool) public connected;
  mapping (bytes32 => uint) public offer; 
  mapping (bytes32 => uint) public deadline; 
  mapping (bytes32 => GameState) public gameState; 

  Enum GameState { FirstMove, SecondMove}; 

  address public owner; 
  uint public bank; 

  mapping (address => uint) public owed; 

  uint public moveTimeline = uint(60400);   // One day

  uint public wager = 10**17;      // .1 ether 

  constructor() 
  public { 
    owner = msg.sender; 
  }

  function broadcastPlayer()
  public { 
    emit LogWantingToPlay(msg.sender); 
  }
  

  // ------------------------------------------------------------------------
  //  Request a pairing with address _to
  // Execution cost: 23965
  // ------------------------------------------------------------------------
  function requestMatch(address _to)
  public 
  payable {
    require(msg.value == wager); 
    bytes32 pairHash = getPairHash(msg.sender, _to);
    require(!connected[pairHash]);
    requested[keccak256(abi.encodePacked(pairHash, msg.sender))] = true;
    deadline[keccak256(abi.encodePacked(pairHash, _to)] = now.add(moveTimeline); 
    emit LogGameRequest(_to, msg.sender);
  }

  // ------------------------------------------------------------------------
  //  User can agree to start a match with _from
  // Execution cost: 50588
  // ------------------------------------------------------------------------
  function firstOffer(address _from, uint _offer)
  public 
  payable {
    require(msg.value == wager); 
    require(_offer > 0 && _offer < wager); 
    bytes32 pairHash = getPairHash(msg.sender, _from);
    require(requested[keccak256(abi.encodePacked(pairHash, _from))]);
    delete requested[keccak256(abi.encodePacked(pairHash, _from))];
    connected[pairHash] = true;
    deadline[pairHash] = moveTimeline.add(now); 
    bytes32 offerHash = keccak256(abi.encodePacked(pairHash, msg.sender)); 
    offer[offerHash] = _offer; 
    gameState[pairHash] = GameState.FirstMove; 
    emit LogNewGame(_from, msg.sender);
  }

  // ------------------------------------------------------------------------
  //  User who initiated game can now accept or deny the offer and create an offer of their own
  // Execution cost: 69873
  // ------------------------------------------------------------------------
  function secondOffer(address _to, bool _accept, uint _offer)
  public { 
    require(_offer > 0 && _offer < wager);  
    bytes32 pairHash = getPairHash(msg.sender, _to); 
    require(gameState[pairHash] == GameState.FirstMove); 
    require(connected[pairHash]); 
    gameState[pairHash] = GameState.SecondMove; 
    bytes32 offerHash = keccak256(abi.encodePacked(pairHash, _to));
    require(offer[offerHash] > 0);
    uint deal = offer[offerHash]; 
    delete offer[offerHash]; 
    if (_accept) { 
      owed[msg.sender] = owed[msg.sender].add(deal); 
      owed[_to] = owed[_to].add(wager.sub(deal)); 
    }
    bytes32 secondOffer = keccak256(abi.encodePacked(pairHash, msg.sender)); 
    offer[secondOffer] = _offer; 
  }

  // ------------------------------------------------------------------------
  //  User who accepted game can accept the offer or deny it
  // Execution cost: 12594
  // ------------------------------------------------------------------------
  function finishGame(address _to, bool _accept)
  public {
    bytes32 pairHash = getPairHash(msg.sender, _to);
    require (gameState[pairHash] == GameState.SecondMove); 
    bytes32 offerHash = keccak256(abi.encodePacked(pairHash, _to));    // Offer for address _to
    require(connected[pairHash]);
    delete connected[pairHash];
    uint deal = offer[offerHash]; 
    delete offer[offerHash]; 
    if (_accept) { 
      owed[msg.sender] = owed[msg.sender].add(deal); 
      owed[_to] = owed[_to].add(wager.sub(deal)); 
    }
    else { 
      bank = bank.add(wager); 
    }
  }

  function withdraw()
  public { 
    uint payout = owed[msg.sender]; 
    require(payout > 0); 
    owed[msg.sender] = 0; 
    msg.sender.transfer(payout); 
  }

  // TODO: Create secure way for players to redeem WEI in case that other player didn't respond
  // @dev Game can end at 4 places: requestMatch(), firstOffer(), secondOffer(), finishGame
  function refundMatch(address _otherPlayer)
  public 
  returns (bool) { 
    bytes32 pairHash = getPairHash(msg.sender, _otherPlayer); 
    // requestMatch() 
    if (requested[getVariableHashFor(pairHash, _otherPlayer)]) { 
      require(!connected[pairHash]);
      require(deadline[getVariableHashFor(pairHash, _otherPlayer)] < now);   // Make sure other players deadline is up
      delete requested[getVariableHashFor(pairHash, _otherPlayer)]; 
      credit(msg.sender, wager);     // Return users wager 
      return true; 
    }
    // firstOffer
    if (gameState[pairHash] == GameState.FirstMove){
      require(deadline[getVariableHashFor(pairHash, _otherPlayer)] < now); 
      bytes32 otherPlayerHash = getVariableHashFor(pairHash, _otherPlayer);
      bytes32 thisPlayerHash = getVariableHashFor(pairHash, msg.sender); 
      if (offer[otherPlayerHash] == 0 && offer[thisPlayerHash] != 0){
        credit(msg.sender, wager); 
        delete connected[pairHash]; 
      }
      if (offer[otherPlayerHash] != 0 && offer[thisPlayerHash] == 0){
        credit(_otherPlayer, wager); 
        delete connected[pairHash]; 
      }
    }
    // second offer 
    if (gameState[pairHash] == GameState.SecondMove) { 

    }

    return false;


  }

  function credit(address _a, uint _amount)
  internal 
  returns (bool) { 
    owed[_a] = owed[_a].add(_amount); 
    return true; 
  }

  // ------------------------------------------------------------------------
  // @notice Finds the common shared hash of these two addresses
  // @dev Use this to store shared game data between two addresses
  // ------------------------------------------------------------------------
  function getPairHash(address _a, address _b)
  public
  pure
  returns (bytes32){
    return (_a < _b) ? keccak256(abi.encodePacked(_a, _b)) :  keccak256(abi.encodePacked(_b, _a));
  }

  // ------------------------------------------------------------------------
  // @notice returns the request hash corresponding to _pairHash and address _b 
  // @dev Variables corresponding to address _b in pairHash(_a, _b)
  // ------------------------------------------------------------------------
  function getVariableHashFor(bytes32 _pairHash, address _user)
  public
  pure
  returns (bytes32){
    return keccak256(abi.encodePacked(pairHash, _user));
  }



  // ------------------------------------------------------------------------
  //  Events
  // ------------------------------------------------------------------------
  event LogWantingToPlay(address indexed _sender); 
  event LogNewGame(address indexed _from, address indexed _acceptor);
  event LogGameRequest(address indexed _to, address indexed _initiator); 





}

  //--------------------------------------------------------------------------------------------------
  // Math operations with safety checks that throw on error
  //--------------------------------------------------------------------------------------------------
library SafeMath {

  //--------------------------------------------------------------------------------------------------
  // Multiplies two numbers, throws on overflow.
  //--------------------------------------------------------------------------------------------------
  function mul(uint256 a, uint256 b) internal pure returns (uint256) {
    if (a == 0) {
      return 0;
    }
    uint256 c = a * b;
    assert(c / a == b);
    return c;
  }

  //--------------------------------------------------------------------------------------------------
  // Integer division of two numbers, truncating the quotient.
  //--------------------------------------------------------------------------------------------------
  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    // assert(b > 0); // Solidity automatically throws when dividing by 0
    // uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold
    return a / b;
  }

  //--------------------------------------------------------------------------------------------------
  // Subtracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
  //--------------------------------------------------------------------------------------------------
  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    assert(b <= a);
    return a - b;
  }

  //--------------------------------------------------------------------------------------------------
  // Adds two numbers, throws on overflow.
  //--------------------------------------------------------------------------------------------------
  function add(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    assert(c >= a);
    return c;
  }

}
