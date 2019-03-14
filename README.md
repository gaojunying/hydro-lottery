# Hydro Lottery
This lottery contract uses Hydro Snowflake Ids (EINs) for creating unique lotteries with rewards setup in HYDRO tokens instead of ETH. It's made of an HydroEscrow contract that holds HYDRO for each unique lottery, a Randomizer contract that generates random numbers with Oraclize for creating unique, secure randomised numbers for selecting winners and a HydroLottery contract that takes care of the main logic. Since we can't generate fully randomised numbers on the blockchain without risking security, we have to use an external oracle which in this case is Oraclize. It charges a small amount of ETH everytime it generates a random number for finishing lotteries and selecting winners. Note that the oracle is free for testnets since Ether holds no value there but you have to use real Ether when deploying the contracts on mainnet.

## Deployment
1. First deploy an Identity Registry contract if you haven't already, a Hydro Token contract and a Randomizer contract. On rinkeby, use the official contract addresses, you still need to deploy a new Randomizer:
    HydroToken: 0x2df33c334146d3f2d9e09383605af8e3e379e180
    IdentityRegistry: 0xa7ba71305bE9b2DFEad947dc0E5730BA2ABd28EA

2. Deploy a new Hydro Lottery contract by setting up the identity registry, hydro token and randomizer addresses in the constructor.

3. Set the Hydro Lottery address on the Randomizer contract by using the `setHydroLottery()` function so that it can call the `endLottery()` function from the main Lottery contract with the randomly generated lottery winner. You can find a complete description of the steps in the tests.

4. Get a Snowflake EIN for you account in order to create a participate in lotteries since it's the main way of interacting with the lotteries instead of addresses. The contract automatically detects if you have an EIN associated with your account.

5. That should be it. You now should be able to use the Hydro Lottery contract.

## Creating a lottery
After setting up the contracts you'll want to create a lottery. The way it's done is simple: approve some HYDRO to the Lottery contract and execute the `createLottery()` function with your desired lottery name, description, hydro price per ticket, hydro reward for the winner (how many tokens the winner gets), the start timestamp, the end timestamp, the fee and the fee receiver address. A fee is optional for those that want to get a portion of the earnings from that lottery. The fee must be between 0 and 100, for instance if you set a fee of 20, the fee receiver address will get the 20% of all the earnings including the lottery reward and the lottery tickets sold. In that case the winner will get 80% of the set hydro reward + an 80% of the earnings from tickets sold to that lottery while the fee receiver gets a 20% from the same sources.

When you run the create lottery function, a new HydroEscrow contract will be created associated to that lottery to hold all the funds raised in a secure independent environment. The only way to extract those tokens is to end the lottery with the `raffle()` function. After the lottery is created, the function will return the lottery ID which you can use to identify that lottery.

## Buying a ticket
Users that want to participate in the lottery will have to buy a ticket by paying the specified hydro price for it, they can only participate once per lottery and they must have an EIN associated with their accounts to do so. To buy a ticket, the user first have to approve the right amount of tokens for purchasing the ticket from the Lottery contract and then using the function `buyTicket()` with the lotteryId. It returns the ticket Id which is the identifier for that particular user.

The ticket must be purchased as long as the lottery is open, within the start and end timestamps. You can get the ticket price for a specific lotteryId from the public mapping `lotteryById` which returns the Lottery object containing the `hydroPrice` parameter which is the price per ticket.

## Ending a lottery
To select a winner from a lottery, the lottery's end timestamp must be reached and it can only be closed by the creator of the lottery. To run the raffle, use the function `raffle()` which initiates the procedure to generate a random number for selecting a winner from the pool of participants with the Randomizer contract that uses Oraclize's random number generation. You must send some Ether to pay for the oracle services, 0.01 ETH should be enough most times although 0.1 ETH is the recommended option to avoid errors. Remember that ETH is testnets is free so you won't lose real money when running the raffle() function. In the mainnet, you'll lose some real ether to execute that function and pay the oracle for its services.

The Randomizer contract creates a query to generate the random number which is received by the Randomizer contract with the `__callback()` function. That callback function receives the securely generated number and calls the `endLottery()` function from Hydro Lottery which selects the winner from the array of participants.

Technically speaking, the number generated by Oraclize is between 0 and the number of participants using WolframAlpha's random functions. So if there are 500 participants after lottery's end time is reached, the Randomizer contract will randomly generate a number between 0 and 500. This function is secure since it can only be initiated by the owner of the lottery and the Randomizer contract only allows executions coming from the HydroLottery contract. The Randomizer contract will execute `endLottery()` from HydroLottery's contract and select the winner while updating the lottery object so that it's closed.

To run the tests, open the file `working oraclize on dev.txt` and follow the steps.

That's it! Enjoy the lottery contract and let me know if you find bugs that must be fixed.
