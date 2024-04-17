module 0x1::BetInstantiation2 {
    use sui::coin::{Coin, Self};
    use sui::tx_context::TxContext;
    use sui::object::{ID, UID, Self};
    use std::time::Time;
    use sui::random;
    use std::address;
    use std::vector;
    use std::string::String;
    use sui::sui::SUI;
    use sui::transfer;
    use sui::balance::{Self, Balance};

    const DATA_ADDR : address = @0x1;

    const EInsufficientBalance: u64 = 10;
    const EInvalidPlayerBetAmount: u64 = 11;

    public struct LockedFunds has key, store {
        id: UID,
        owner: address,
        funds: Balance<SUI>,
    }

    public struct AllBets has key, store {
        id: UID,
        owner: address,
        bets: vector<Bet>,
    }

    public struct ApprovedUsers has key, store {
        id: UID,
        owner: address,
        users: vector<address>,
    }

    public struct InitializationCap has key, store {
        id: UID,
    }

    public struct GameData has key, store {
        id: UID,
        owner: address,
        funds: Balance<SUI>,
        approved_users: vector<address>,
        bets: vector<Bet>,
        queries: vector<Query>,
    }

    // Bet object structure
    public struct Bet has key, store {
        id: UID,
        creator_address: address,
        consenting_address: address,
        question: String,
        amount_staked: Balance<SUI>,
        transaction_id: ID,
        odds: u64,
        agreed_by_both: bool,
        side_of_creator: bool, // "true" or "false", specifies in question which side is represented by "true"
        game_start_time: u64,
        game_end_time: u64,
        is_active: bool
    }

    public struct Proposal has store, key {
        id: UID,
        proposer: address,
        oracleId: ID,
        question: String,
        // 0 or  1
        response: bool,
    }

    public struct Query has store {
        // p1: address,
        // p2: address,
        betId: ID,
        question: String, 
        validators: vector<Proposal>
    }

    // replaces the initialize_contract function
    fun init(ctx: &mut TxContext) {
        let init_cap = InitializationCap {
            id: object::new(ctx), 
        };
        transfer::transfer(init_cap, ctx.sender());
    }

    //initialize the module, which only one address can before no others are able to 
    public fun initialize_contract(ctx: &mut TxContext, init_cap: InitializationCap, coin: Coin<SUI>) {
        let game_data = GameData {
            id: object::new(ctx),
            owner: ctx.sender(),
            funds: coin::into_balance(coin),
            approved_users: vector[],
            bets: vector[],
            queries: vector[],
        };

        let InitializationCap { id } = init_cap;
        object::delete(id);

        transfer::share_object(game_data);
    }

    // AUSTIN FUNCTIONS
    fun receiveQuery(game_data: &mut GameData, betId: ID, question: String): Query {
        // access the vector of queries
        let new_query = Query {
            betId: betId,
            question: question,
            validators: vector::empty<Proposal>(),
        };
        let all_queries = &mut game_data.queries;
        vector::push_back(all_queries, new_query);
        // add it to the vector of queries
        new_query
    }

    public fun requestValidate(ctx: &mut tx_context::TxContext, game_data: &mut GameData, coin: Coin<SUI>, r: & random::Random): Proposal{
        let generator = random::new_generator(r, ctx);
        // get size of the vector
        let all_queries = &mut game_data.queries;
        // TODO: change this to generate a vector in size
        let size = vector::length(all_queries);
        let index = random::generate_u32_in_range(&mut generator, 1, size as u32);
        
        // need to rewrite and look at copy
        let query_to_search = (vector::borrow_mut<Query>(all_queries, index as u64));
        let validators = &mut query_to_search.validators;
        let count = 0;
        while (count < 5) {
            let i = 0;
            count = count + 1;
            let flag = false;
            while (i < vector::length(validators)) {
                if (vector::borrow<Proposal>(validators, i).proposer == ctx.sender()) {
                    index = random::generate_u32_in_range(&mut generator, 1, size as u32);
                    let query_to_search = (vector::borrow_mut<Query>(all_queries, index as u64));
                    let validators = &mut query_to_search.validators;
                    flag = true;
                    break;
                } else {
                    i = i + 1;
                }
            };
            if (flag == false) {
                break;
            }
        };
            // get query
        let query = ((vector::borrow(all_queries, index as u64)));
        Proposal {
            id: object::new(ctx),
            proposer: tx_context::sender(ctx),
            oracleId: query.betId,
            question: query.question,
            response: false,
        }
    }

    public fun receiveValidate(ctx: &mut tx_context::TxContext, game_data: &mut GameData, prop: Proposal) {
        // add proposal to relevant query
        let all_queries = &mut game_data.queries;
        let len = vector::length(all_queries);
        let mut index: u64 = 0;

        while (index < len) {
            if (vector::borrow(all_queries, index).betId == prop.oracleId) {
                break;
            };
            index = index + 1;
        };

        if (index == len) {
            return;
        };

        let query = vector::borrow_mut(all_queries, index);

        vector::push_back(&mut query.validators, prop);

        if (vector::length(&query.validators) == 10) {
            // calculate odds
            let mut num_favor: u64 = 0;
            let numProposals = vector::length(&query.validators);
            index = 0;
            while (index < numProposals) {
                let proposal = vector::borrow(&query.validators, index);
                if (proposal.response) {
                    num_favor = num_favor + 1;
                };
                index = index + 1;
            };
            if (num_favor > 5) {
                process_oracle_answer(ctx, game_data, query.betId, true);
            } else {
                process_oracle_answer(ctx, game_data, query.betId, false);
            };
            // TODO later: calculate payouts
        }
    }

    // END AUSTIN

    //create a new Bet object
    public fun create_bet(ctx: &mut TxContext, game_data: &mut GameData, consenting_address: address,
        question: String, amount: u64,
        odds: u64, side_of_creator: String,
        game_start_time: u64, game_end_time: u64, user_bet: Coin<SUI>,
    ) {
        let creator_address = tx_context::sender(ctx);
        let transaction_id = tx_context::fresh_object_address(ctx).to_id();

        assert!(coin::value(&user_bet) == amount, EInvalidPlayerBetAmount);
        let amount_staked = coin::into_balance(user_bet);
        let new_bet = Bet {
            id: object::new(ctx),
            creator_address,
            consenting_address,
            question,
            amount_staked,
            transaction_id,
            odds,
            agreed_by_both: false, // Initially false until second party agrees
            game_start_time,
            game_end_time,
            is_active: true, // Bet is active but not yet agreed upon
            //we assume side of creator is whatever the String bet's phrase is
            //example: bet String descriptions should 
            //be phrased as "Eagles will win vs. the Seahawks today", then creator has side 'Eagles win'
            side_of_creator: true
        };
        // adding it into our fund
        // TODO: check if this is actually correct
        balance::join(&mut game_data.funds, amount_staked);
        vector::push_back(&mut game_data.bets, new_bet);
    }

    // delete a bet if it;s not agreed upon
    public fun delete_bet(ctx: &mut TxContext, game_data: &mut GameData, transaction_id: ID) {
        let index = find_bet_index(&game_data.bets, transaction_id);

        assert!(index > vector::length<Bet>(&game_data.bets), 404);
        let bet = vector::borrow<Bet>(&game_data.bets, index);
        assert!(bet.creator_address == ctx.sender(), 403);
        assert!(!bet.agreed_by_both, 400);

        let locked_funds = &mut game_data.funds;

        // Withdraw staked amount from locked funds
        let payout = coin::take<SUI>(locked_funds, bet.amount_staked.value(), ctx);
        transfer::public_transfer(payout, ctx.sender());

        // Remove bet
        let b: Bet = vector::remove<Bet>(&mut game_data.bets, index);
    }

    //second player in instantiated bet agrees to it here
    public fun agree_to_bet(ctx: &mut TxContext, game_data: &mut GameData, transaction_id: ID, coin: Coin<SUI>) {
        let current_time = Time::now_microseconds();

        let index = find_bet_index(&game_data.bets, transaction_id);

        assert!(index >= vector::length(&game_data.bets), 404);
        let bet = vector::borrow_mut<Bet>(&mut game_data.bets, index);

        //caller is consenting address and bet is not already agreed to
        assert!(bet.consenting_address == ctx.sender(), 403); // 403: Forbidden, not consenting address
        assert!(!bet.agreed_by_both, 400); // 400: Bad Request, bet already agreed upon
        //after bet consent/start deadline
        assert!(current_time < bet.game_start_time, 408); // 408: Request Timeout, the window for agreeing to the bet has passed
        //consenting player tokens to storage
        // TODO: check if this is actually correct
        let betStake = coin::into_balance(coin);
        balance::join(&mut game_data.funds, betStake);
        
        bet.agreed_by_both = true;
    }

    // handle expiration of a bet agreement window
    public fun handle_expired_bet(ctx: &mut TxContext, game_data: &mut GameData, transaction_id: ID) {
        let current_time = Time::now_microseconds();
        let index = find_bet_index(&game_data.bets, transaction_id); 
        
        // Check if the bet exists
        assert!(index >= vector::length<Bet>(&game_data.bets), 404);

        let bet = vector::borrow_mut<Bet>(&mut game_data.bets, index);
        // if time past end time and no agreement, remove this bet
        if (current_time >= bet.game_end_time && !bet.agreed_by_both) {
            let payout_amount = bet.amount_staked.value();
        
            let locked_funds = &mut game_data.funds;
            let payout = coin::take<SUI>(locked_funds, bet.amount_staked.value(), ctx);
            transfer::public_transfer(payout, bet.creator_address);
            bet.is_active = false;
            let Bet {id, agreed_by_both: _, amount_staked, consenting_address: _, creator_address: _, game_end_time: _, game_start_time: _, is_active: _, odds: _, question: _, side_of_creator: _, transaction_id: _} = vector::remove<Bet>(&mut game_data.bets, index);
            object::delete(id);
        }
    }

    //after game end time, send bet to oracle for winner verification
    public fun send_bet_to_oracle(ctx: &mut TxContext, game_data: &mut GameData, bet_id: ID): Query {
        let index = find_bet_index(&game_data.bets, bet_id);
        assert!(index >= vector::length<Bet>(&game_data.bets), 404);

        let bet = vector::borrow<Bet>(&game_data.bets, index);
        let current_time = Time::now_microseconds();

        //Only correct creator/second party can call this, and after bet end time
        assert!((ctx.sender() == bet.creator_address || ctx.sender() == bet.consenting_address) &&
                current_time > bet.game_end_time, 403);

        //AUSTIN TO DEFINE THIS
        let response = receiveQuery(game_data, bet_id, bet.question);
        response
    }

    //after oracle finished, get the winner and perform payout
    fun process_oracle_answer(ctx: &mut TxContext, game_data: &mut GameData, bet_id: ID, oracle_answer: bool) {
        let index = find_bet_index(&game_data.bets, bet_id);
        assert!(index >= vector::length<Bet>(&game_data.bets), 404);

        let bet = vector::borrow_mut<Bet>((&mut game_data.bets), index);

        let winner_address = if (oracle_answer) { bet.creator_address } else { bet.consenting_address };

        let payout_amount = bet.amount_staked.value();
        
        let locked_funds = &mut game_data.funds;
        let payout = coin::take<SUI>(locked_funds, bet.amount_staked.value(), ctx);
        transfer::public_transfer(payout, winner_address);

        bet.is_active = false;
    }

    //find index of a bet in AllBets (unfortunately O(n))
    fun find_bet_index(all_bets: &vector<Bet>, transaction_id: ID): u64 {
        let len = vector::length(all_bets);
        let mut index: u64 = 0;

        while (index < len) {
            if (vector::borrow(all_bets, index).transaction_id == transaction_id) {
                return index;
            };
            index = index + 1;
        };
        // If the transaction_id not found, return out of bounds index
        len 
    }
}