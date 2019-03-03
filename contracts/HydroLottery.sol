pragma solidity ^0.5.0;

import './HydroEscrow.sol';
import './HydroTokenTestnetInterface.sol';
import './IdentityRegistryInterface.sol';
import './OraclizeAPI.sol';

// Rinkeby testnet addresses
// HydroToken: 0x2df33c334146d3f2d9e09383605af8e3e379e180
// IdentityRegistry: 0xa7ba71305bE9b2DFEad947dc0E5730BA2ABd28EA
// Most recent HydroLottery deployed address: 0x001328288dd358644e289f48ec4ef0bc3139a2d2

// TODO Uncomment oraclize constructor

/// @notice The Hydro Lottery smart contract to create decentralized lotteries for accounts that have an EIN Snowflake ID assciated with them. All payments are done in HYDRO instead of Ether.
/// @author Merunas Grincalaitis <merunasgrincalaitis@gmail.com>
contract HydroLottery is usingOraclize {
    event LotteryStarted(uint256 indexed id, uint256 indexed beginningDate, uint256 indexed endDate);
    event LotteryEnded(uint256 indexed id, uint256 indexed endTimestamp, uint256 indexed einWinner);
    event Raffle(uint256 indexed lotteryId, bytes32 indexed queryId);

    struct Lottery {
        bool exists;
    	uint256 id;
    	bytes32 name;
    	string description;
    	uint256 hydroPrice;
        uint256 hydroReward;
    	uint256 beginningDate;
    	uint256 endDate;
        uint256 einOwner; // Instead of using the address we use EIN for the owner of the lottery
    	// The escrow contract will setup a percentage of the funds raised for a fee that will be paid to the user that created the lottery or one he specifies
    	uint256 fee;
    	address feeReceiver;
    	address escrowContract;
        // The unique EINs of those that participate in this lottery. You can get the length of this array to calculate how many users are participating in this lottery
        uint256[] einsParticipating;
    	// Assigns a snowflakeId => tickedID which is a unique identifier for that participation. Only one ticket per EIN for now.
    	mapping(uint256 => uint256) assignedLotteries;
    	uint256 einWinner;
    }

    IdentityRegistryInterface public identityRegistry;
    HydroTokenTestnetInterface public hydroToken;

    // Lottery id => Lottery struct
    mapping(uint256 => Lottery) public lotteryById;
    Lottery[] public lotteries;
    uint256[] public lotteryIds;

    // Query ID for ending lotteries => Lottery ID to idenfity ending lotteries with oraclize's callback
    mapping(bytes32 => uint256) public endingLotteryIdByQueryId;

    // Escrow contract's address => lottery number
    mapping(address => uint256) public escrowContracts;
    address[] public escrowContractsArray;

    constructor(address _identityRegistryAddress, address _tokenAddress) public {
        require(_identityRegistryAddress != address(0), 'The identity registry address is required');
        require(_tokenAddress != address(0), 'You must setup the token rinkeby address');
        hydroToken = HydroTokenTestnetInterface(_tokenAddress);
        identityRegistry = IdentityRegistryInterface(_identityRegistryAddress);
        // TODO Uncomment this when the contract is completed
        /* oraclize_setProof(proofType_Ledger); */
    }

    /// @notice Defines the lottery specification requires a HYDRO payment that will be used as escrow for this lottery. The escrow is a separate contract to hold people’s HYDRO funds not ether. Remember to approve() the right amount of HYDRO for this contract to set the hydro reward for the lottery.
    /// @param _name The lottery name
    /// @param _description What the lottery is about
    /// @param _hydroPricePerTicket How much each user has to pay to participate in the lottery, the price per ticket in HYDRO
    /// @param _hydroReward The HYDRO reward set by the owner of the lottery, the one that created it. Those are the tokens that the winner gets
    /// @param _beginningTimestamp When the lottery starts in timestamp
    /// @param _endTimestamp When the lottery ends in timestamp
    /// @param _fee The percentage from 0 to 100 that the owner takes for each ticket bought
    /// @param _feeReceiver The address that will receive the fee for each ticket bought
    /// @return uint256 Returns the new lottery identifier just created
    function createLottery(bytes32 _name, string memory _description, uint256 _hydroPricePerTicket, uint256 _hydroReward, uint256 _beginningTimestamp, uint256 _endTimestamp, uint256 _fee, address payable _feeReceiver) public returns(uint256) {
        uint256 newLotteryId = lotteries.length;

        require(identityRegistry.getEIN(msg.sender) != 0, 'The owner must have an EIN number');
        require(_fee >= 0 && _fee <= 100, 'The fee must be between 0 and 100 (in percentage without the % symbol)');
        require(hydroToken.balanceOf(msg.sender) >= _hydroReward, 'You must have enough token funds for the reward');
        require(_hydroReward > 0, 'The reward must be larger than zero');
        require(_beginningTimestamp >= now, 'The lottery must start now or in the future');
        require( _endTimestamp > _beginningTimestamp, 'The lottery must end after the start not earlier');
        require(_feeReceiver != address(0), 'You need to specify the fee receiver even if its yourself');

        // Creating the escrow contract that will hold HYDRO tokens for this lottery exclusively as a safety feature
        HydroEscrow newEscrowContract = new HydroEscrow(_endTimestamp, address(hydroToken), _hydroReward, _fee, _feeReceiver);
        escrowContracts[address(newEscrowContract)] = newLotteryId;
        escrowContractsArray.push(address(newEscrowContract));

        uint256 allowance = hydroToken.allowance(msg.sender, address(this));
        // Transfer HYDRO tokens to the escrow contract from the msg.sender's address with transferFrom() until the lottery is finished
        // Use transferFrom() after the approval has been manually done. Checking the allowance first.
        require(allowance >= _hydroReward, 'Your allowance is not enough. You must approve() the right amount of HYDRO tokens for the reward.');
        require(hydroToken.transferFrom(msg.sender, address(newEscrowContract), _hydroReward), 'The token transfer must be successful');

        Lottery memory newLottery = Lottery({
            exists: true,
            id: newLotteryId,
            name: _name,
            description: _description,
            hydroPrice: _hydroPricePerTicket,
            hydroReward: _hydroReward,
            beginningDate: _beginningTimestamp,
            endDate: _endTimestamp,
            einOwner: identityRegistry.getEIN(msg.sender),
            fee: _fee,
            feeReceiver: _feeReceiver,
            escrowContract: address(newEscrowContract),
            einsParticipating: new uint256[](0),
            einWinner: 0
        });

        lotteries.push(newLottery);
        lotteryById[newLotteryId] = newLottery;
        lotteryIds.push(newLotteryId);

        emit LotteryStarted(newLotteryId, _beginningTimestamp, _endTimestamp);

        return newLotteryId;
    }

    /// @notice Creates a unique participation ticket ID for a lottery and stores it inside the proper Lottery struct. You need to approve the right amount of tokens to this contract before buying the lottery ticket using your HYDRO tokens associated with your address. Note, you can only buy 1 ticket per lottery for now.
    /// @param _lotteryNumber The unique lottery identifier used with the mapping lotteryById
    /// @return uint256 Returns the ticket id that you just bought
    function buyTicket(uint256 _lotteryNumber) public returns(uint256) {
        uint256 ein = identityRegistry.getEIN(msg.sender);
        uint256 allowance = hydroToken.allowance(msg.sender, address(this));
        uint256 ticketPrice = lotteryById[_lotteryNumber].hydroPrice;
        address escrowContract = lotteryById[_lotteryNumber].escrowContract;

        require(ein != 0, 'You must have an EIN snowflake identifier associated with your address when buying tickets');
        require(lotteryById[_lotteryNumber].exists, 'The lottery must exist for you to participate in it by buying a ticket');
        require(allowance >= ticketPrice, 'Your allowance is not enough. You must approve() the right amount of HYDRO tokens for the price of this lottery ticket.');
        require(hydroToken.transferFrom(msg.sender, escrowContract, ticketPrice), 'The ticket purchase for this lottery must be successful when transfering tokens');

        // Update the lottery parameters
        uint256 ticketId = lotteryById[_lotteryNumber].einsParticipating.length;
        lotteryById[_lotteryNumber].einsParticipating.push(ticketId);
        lotteryById[_lotteryNumber].assignedLotteries[ein] = ticketId;

        return ticketId;
    }

    /// @notice Randomly selects one Snowflake ID associated to a lottery as the winner of the lottery and must be called by the owner of the lottery when the endDate is reached or later
    function raffle(uint256 _lotteryNumber) public {
        Lottery memory lottery = lotteryById[_lotteryNumber];
        uint256 senderEIN = identityRegistry.getEIN(msg.sender);

        require(lottery.einWinner == 0, 'The raffle for this lottery has been completed already');
        require(now > lottery.endDate, 'You must wait until the lottery end date is reached before selecting the winner');
        require(senderEIN == lottery.einOwner, 'The raffle must be executed by the owner of the lottery');
        generateNumberWinner(_lotteryNumber);
    }

    /// @notice Generates a random number between 1 and 10 both inclusive.
    /// Must be payable because oraclize needs gas to generate a random number.
    /// Can only be executed when the lottery ends.
    /// @param _lotteryNumber The ID of the lottery to finish
    function generateNumberWinner(uint256 _lotteryNumber) internal {
      uint256 numberRandomBytes = 7;
      uint256 delay = 0;
      uint256 callbackGas = 200000;

      bytes32 queryId = oraclize_newRandomDSQuery(delay, numberRandomBytes, callbackGas);
      endingLotteryIdByQueryId[queryId] = _lotteryNumber;
      emit Raffle(_lotteryNumber, queryId);
    }

   /// @notice Callback function that gets called by oraclize when the random number is generated
   /// @param _queryId The query id that was generated to proofVerify
   /// @param _result String that contains the number generated
   /// @param _proof A string with a proof code to verify the authenticity of the number generation
   function __callback(
      bytes32 _queryId,
      string memory  _result,
      bytes memory _proof
   ) public oraclize_randomDS_proofVerify(_queryId, _result, _proof) {

      // Checks that the sender of this callback was in fact oraclize
      require(msg.sender == oraclize_cbAddress(), 'The callback function can only be executed by oraclize');

      uint256 numberWinner = (uint256(keccak256(bytes(_result)))%10+1);
      uint256 lotteryId = endingLotteryIdByQueryId[_queryId];

      // Select the winner based on his position in the array of participants
      uint256 einWinner = lotteryById[lotteryId].einsParticipating[numberWinner];
      emit LotteryEnded(lotteryId, now, einWinner);
   }

   /// @notice Returns all the lottery ids
   /// @return uint256[] The array of all lottery ids
   function getLotteryIds() public view returns(uint256[] memory) {
       return lotteryIds;
   }

   /// @notice To get the ticketId given the lottery and ein
   /// @param lotteryId The id of the lottery
   /// @param ein The ein of the user that purchased the ticket
   /// @return ticketId The Id of the ticket purchased, zero is also a valid identifier if there are more than 1 tickets purchased
   function getTicketIdByEin(uint256 lotteryId, uint256 ein) public view returns(uint256 ticketId) {
       ticketId = lotteryById[lotteryId].assignedLotteries[ein];
   }

   /// @notice To get the array of eins participating in a lottery
   /// @param lotteryId The id of the lottery that you want to examine
   /// @return uint256[] The array of EINs participating in the lottery that have purchased a ticket
   function getEinsParticipatingInLottery(uint256 lotteryId) public view returns(uint256[] memory) {
       return lotteryById[lotteryId].einsParticipating;
   }
}
