module 0x1::BetInstantiation2 {
    use sui::coin::{Coin, Self};
    use sui::clock::{Self, Clock};
    use sui::random;
    use std::string::String;
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};

    const EInsufficientBalance: u64 = 10;
    const ECallerNotInstantiator: u64 = 21;

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
        amount_staked_value: u64,
        bet_id: ID,
        odds: u64,
        agreed_by_both: bool,
        //side of creator is the affirmative of whatever the bet says
        //ex: Eagles defeat Seahawks means instantiator is on Eagles win side
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

        transfer::transfer(init_cap, tx_context::sender(ctx));
    }

    //initialize the module, which only one address can before no others are able to 
    public fun initialize_contract(ctx: &mut TxContext, init_cap: InitializationCap, coin: Coin<SUI>) {
        let game_data = GameData {
            id: object::new(ctx),
            owner: tx_context::sender(ctx),
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
    fun receiveQuery(game_data: &mut GameData, bet_id: ID, question: String) {
        // access the vector of queries
        let new_query = Query {
            betId: bet_id,
            question: question,
            validators: vector::empty<Proposal>(),
        };
        let all_queries = &mut game_data.queries;
        vector::push_back(all_queries, new_query);
    }

    public fun requestValidate(ctx: &mut tx_context::TxContext, game_data: &mut GameData, coin: Coin<SUI>, r: & random::Random): Proposal{
        let mut generator = random::new_generator(r, ctx);
        // get size of the vector
        let all_queries = &mut game_data.queries;
        // TODO: change this to generate a vector in size
        let size = vector::length(all_queries);
        let mut index = random::generate_u32_in_range(&mut generator, 1, (size as u32));
        
        // need to rewrite and look at copy
        let query_to_search = (vector::borrow_mut<Query>(all_queries, (index as u64)));
        let mut validators = &mut query_to_search.validators;
        let mut count = 0;
        while (count < 5) {
            let mut i = 0;
            count = count + 1;
            let mut flag = false;
            while (i < vector::length(validators)) {
                if (vector::borrow<Proposal>(validators, i).proposer == tx_context::sender(ctx)) {
                    index = random::generate_u32_in_range(&mut generator, 1, size as u32);
                    validators = &mut (vector::borrow_mut<Query>(all_queries, (index as u64))).validators;
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
        assert!(count < 5, EInsufficientBalance);
            // get query
        let query = ((vector::borrow(all_queries, index as u64)));
        let amount_staked = coin::into_balance(coin);
        // adding the stake to the game balance
        balance::join(&mut game_data.funds, amount_staked);
        let new_proposal = Proposal {
            id: object::new(ctx),
            proposer: tx_context::sender(ctx),
            oracleId: query.betId,
            question: query.question,
            response: false,
        };
        new_proposal
    }

    public fun receiveValidate(ctx: &mut tx_context::TxContext, bet: &mut Bet, game_data: &mut GameData, prop: Proposal) {
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

        assert!(index < len, ECallerNotInstantiator);

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
            let mut wrong_answers = 0;
            if (num_favor > 5) {
                wrong_answers = numProposals - num_favor;
            } else {
                wrong_answers = num_favor;
            };
            let right_answers = numProposals - wrong_answers;

            let amount_earned = 10 + (wrong_answers * 10) / right_answers;

            // doing the payouts
            index = 0;
            while (index < numProposals) {
                let proposal = vector::borrow(&query.validators, index);
                // wrong_answer
                if ((proposal.response && num_favor <= 5) || (!proposal.response && num_favor > 5)) {
                    let locked_funds = &mut game_data.funds;
                    let payout = coin::take<SUI>(locked_funds, amount_earned, ctx);
                    transfer::public_transfer(payout, proposal.proposer);
                }
            };

            if (num_favor > 5) {
                process_oracle_answer(ctx, query.betId, game_data, true);
            } else {
                process_oracle_answer(ctx, query.betId, game_data, false);
            };
            // TODO later: calculate payouts
        }
    }

    // END AUSTIN

    //create a new Bet object
    public fun create_bet(ctx: &mut TxContext, game_data: &mut GameData, consenting_address: address,
        question: String, amount: u64,
        odds: u64, 
        game_start_time: u64, game_end_time: u64, user_bet: Coin<SUI>,
    ) {
        let creator_address = tx_context::sender(ctx);
        let bet_id = tx_context::fresh_object_address(ctx).to_id();
        assert!(tx_context::sender(ctx) == game_data.owner, ECallerNotInstantiator);
        assert!(coin::value(&user_bet) == amount, EInsufficientBalance);
        let amount_staked = coin::into_balance(user_bet);
        let amount_staked_value = amount_staked.value();
        balance::join(&mut game_data.funds, amount_staked);
        let new_bet = Bet {
            id: object::new(ctx),
            creator_address,
            consenting_address,
            question,
            amount_staked_value,
            bet_id,
            odds,
            agreed_by_both: false, // Initially false until second party agrees
            game_start_time,
            game_end_time,
            is_active: true, // Bet is active but not yet agreed upon
            //we assume side of creator is whatever the String bet's phrase is
            //example: bet String descriptions should 
            //be phrased as "Eagles will win vs. the Seahawks today", then creator has side 'Eagles win'
        };
        // adding it into our fund
        // TODO: check if this is actually correct
        vector::push_back(&mut game_data.bets, new_bet);
    }

    // delete a bet if it;s not agreed upon
    public fun delete_bet(ctx: &mut TxContext, bet: &mut Bet, game_data: &mut GameData) {
        let index = find_bet_index(&game_data.bets, bet.bet_id);

        assert!(index > vector::length<Bet>(&game_data.bets), 404);
        assert!(bet.creator_address == ctx.sender(), 403);
        assert!(!bet.agreed_by_both, 400);

        let locked_funds = &mut game_data.funds;

        // Withdraw staked amount from locked funds
        let payout = coin::take<SUI>(locked_funds, bet.amount_staked_value, ctx);
        transfer::public_transfer(payout, ctx.sender());

        // Remove bet
        bet.is_active = false;
    }

    //second player in instantiated bet agrees to it here
    public fun agree_to_bet(ctx: &mut TxContext, bet: &mut Bet, clock: &Clock, game_data: &mut GameData, coin: Coin<SUI>) {
        let current_time = clock::timestamp_ms(clock);
        let index = find_bet_index(&game_data.bets, bet.bet_id);
        assert!(index >= vector::length(&game_data.bets), 404);
        
        //caller is consenting address and bet is not already agreed to
        assert!(bet.consenting_address == ctx.sender(), 403); // 403: Forbidden, not consenting address
        assert!(!bet.agreed_by_both, 400); // 400: Bad Request, bet already agreed upon
        assert!(bet.is_active, 402); //402: Deprecated bet
        assert!(current_time < bet.game_start_time, 408); // 408: Request Timeout, the window for agreeing to the bet has passed
        //consenting player tokens to storage
        // TODO: check if this is actually correct
        let betStake = coin::into_balance(coin);
        balance::join(&mut game_data.funds, betStake);
        
        bet.agreed_by_both = true;
    }

    // handle expiration of a bet agreement window
    public fun handle_expired_bet(ctx: &mut TxContext, bet: &mut Bet, clock: &Clock, game_data: &mut GameData) {
        let current_time = sui::clock::timestamp_ms(clock);
        let index = find_bet_index(&game_data.bets, bet.bet_id); 
        
        // Check if the bet exists
        assert!(index >= vector::length<Bet>(&game_data.bets), 404);

        // if time past end time and no agreement, remove this bet
        if (current_time >= bet.game_end_time && !bet.agreed_by_both) {
            let locked_funds = &mut game_data.funds;
            let payout = coin::take<SUI>(locked_funds, bet.amount_staked_value, ctx);
            transfer::public_transfer(payout, bet.creator_address);
            bet.is_active = false;
        }
    }

    //after game end time, send bet to oracle for winner verification
    public fun send_bet_to_oracle(ctx: &mut TxContext, bet: &mut Bet, clock: &Clock, game_data: &mut GameData, bet_id: ID) {
        let index = find_bet_index(&game_data.bets, bet_id);
        assert!(index >= vector::length<Bet>(&game_data.bets), 404);

        let current_time = clock::timestamp_ms(clock);

        //Only correct creator/second party can call this, and after bet end time
        assert!((ctx.sender() == bet.creator_address || ctx.sender() == bet.consenting_address) &&
                current_time > bet.game_end_time, 403);

        //AUSTIN TO DEFINE THIS
        receiveQuery(game_data, bet_id, bet.question);
    }

    //after oracle finished, get the winner and perform payout
    fun process_oracle_answer(ctx: &mut TxContext, betId: ID, game_data: &mut GameData, oracle_answer: bool) {
        let index = find_bet_index(&game_data.bets, betId);
        assert!(index >= vector::length<Bet>(&game_data.bets), 404);
        let bet = vector::borrow_mut(&mut game_data.bets, index);

        let winner_address = if (oracle_answer) { bet.creator_address } else { bet.consenting_address };
        let locked_funds = &mut game_data.funds;
        let payout = coin::take<SUI>(locked_funds, bet.amount_staked_value, ctx);
        transfer::public_transfer(payout, winner_address);

        bet.is_active = false;
    }

    //find index of a bet in AllBets (unfortunately O(n))
    fun find_bet_index(all_bets: &vector<Bet>, bet_id: ID): u64 {
        let len = vector::length(all_bets);
        let mut index: u64 = 0;

        while (index < len) {
            if (vector::borrow(all_bets, index).bet_id == bet_id) {
                return index;
            };
            index = index + 1;
        };
        // If the bet_id not found, return out of bounds index
        len 
    }
}