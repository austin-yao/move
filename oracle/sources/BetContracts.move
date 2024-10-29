module 0x0::BetInstantiation2;


    use sui::coin::{Coin, Self};
    use sui::clock::{Self, Clock};
    use sui::random;
    use std::string::String;
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::dynamic_object_field::{Self as dof};
    use sui::vec_set::{Self, VecSet};
    use sui::vec_map::{Self, VecMap};
    use sui::priority_queue::{Self, PriorityQueue};
    use sui::bag::{Self, Bag};
    use sui::table::{Self, Table};
    use sui::object_table::{Self, ObjectTable};
    use sui::table_vec::{Self, TableVec};

    // TODO: for randomization, we can make a mapping from 
    // number to ID, choose a random number and use that ID.
    // grow the set of numbers if we are running out

    const EInsufficientBalance: u64 = 10;
    const ENoQueryToValidate: u64 = 11;
    const EBetNotFound: u64 = 12;
    const ECallerNotInstantiator: u64 = 13;
    const EValidationError: u64 = 14;
    const EWrongFundAmount: u64 = 15;

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

    // GameData is an object, all_queries and approved_users cannot be too big
    // store them as dynamic fields
    public struct GameData has key, store {
        id: UID,
        owner: address,
        funds: Balance<SUI>,
        approved_users: Bag,
        all_queries: ObjectTable<ID, Query>,
        all_bets: ObjectTable<ID, Bet>,
        query_count: u64,
        num_to_query: Table<u64, ID>,
        available_nums: TableVec<u64>
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
        query_id: ID,
    }

    public struct Query has store, key {
        // p1: address,
        // p2: address,
        id: UID,
        betId: ID,
        question: String, 
        // change validators into a mapping from sender to proposal
        validators: VecMap<address, Proposal>
    }

    // replaces the initialize_contract function
    fun init(ctx: &mut TxContext) {
        let init_cap = InitializationCap {
            id: object::new(ctx), 
        };

        transfer::transfer(init_cap, tx_context::sender(ctx));
    }

    //initialize the module, which only one address can before no others are able to 
    public fun initialize_contract(init_cap: InitializationCap, coin: Coin<SUI>, ctx: &mut TxContext) {
        let game_data = GameData {
            id: object::new(ctx),
            owner: tx_context::sender(ctx),
            funds: coin::into_balance(coin),
            approved_users: bag::new(ctx),
            all_queries: object_table::new<ID, Query>(ctx),
            all_bets: object_table::new<ID, Bet>(ctx),
            query_count: 0,
            num_to_query: table::new<u64, ID>(ctx),
            available_nums: table_vec::empty<u64>(ctx)
        };

        let InitializationCap { id } = init_cap;
        object::delete(id);

        // sharing ok because it is only modifiable by methods that we define
        // this keeps track of all the data for the application
        transfer::share_object(game_data);
    }

    public fun test(init_cap: InitializationCap, ctx: &mut TxContext) {
        let InitializationCap { id } = init_cap;
        object::delete(id);
    }

    // AUSTIN FUNCTIONS
    /*
        called by the application to send a query up for betting
    */
    fun receiveQuery(game_data: &mut GameData, bet_id: ID, question: String, ctx: &mut TxContext) {
        // access the vector of queries
        let new_query = Query {
            id: object::new(ctx),
            betId: bet_id,
            question: question,
            validators: vec_map::empty<address, Proposal>()
        };
        let temp = new_query.id.to_inner();
        game_data.all_queries.add(temp, new_query);
        if (game_data.available_nums.length() == 0) {
            // increment query_count
           game_data.query_count = game_data.query_count + 1;
            game_data.num_to_query.add(game_data.query_count, temp);
        } else {
            let count = game_data.available_nums.pop_back();
            game_data.num_to_query.add(game_data.query_count, temp);
        };
    }
    
    public fun requestValidate(game_data: &mut GameData, ctx: &mut TxContext): Proposal {
        // TODO: introduce randomness. For now, only choose the first available one
        let mut i = 1;
        let sender = tx_context::sender(ctx);
        let proposal: Proposal;
        while (i < game_data.query_count) {
            let query_id = game_data.num_to_query.borrow(i);
            let mut query = game_data.all_queries.borrow_mut(*query_id);
            if (query.validators.contains(&sender)) {
                i = i + 1;
                continue;
            } else {
                break;
            };
        };

        assert!(i < game_data.query_count, ENoQueryToValidate);

        let query_id = game_data.num_to_query.borrow(i);
        let mut query = game_data.all_queries.borrow_mut(*query_id);
        proposal = Proposal {
            id: object::new(ctx),
            proposer: sender,
            oracleId: query.betId,
            question: query.question,
            response: false,
            query_id: *query_id
        };
        proposal
    }
    
    // TODO: rewrite this function
    public fun receiveValidate(bet: &mut Bet, game_data: &mut GameData, prop: Proposal, coin: Coin<SUI>, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        let prop_query_id = prop.query_id;

        // check that the bet and query exist
        assert!(game_data.all_bets.contains(bet.id.to_inner()), EBetNotFound);
        assert!(game_data.all_queries.contains(prop.query_id), EBetNotFound);

        let mut query = game_data.all_queries.borrow_mut(prop.query_id);

        // check that the sender hasn't already validated this one
        assert!(!query.validators.contains(&sender), EValidationError);
        query.validators.insert(sender, prop);

        assert!(coin.value() == 10, EWrongFundAmount);
        let amount_staked = coin::into_balance(coin);
        balance::join(&mut game_data.funds, amount_staked);
        
        // always need 11 validators.
        // can make this into a parameter set in game_data as well.
        if (query.validators.size() == 11) {
            let mut num_in_favor = 0;

            // deconstruct the query
            let actual_query = game_data.all_queries.remove(prop_query_id);
            let Query {id, betId, question: _, validators} = move actual_query;
            let (vals, mut props) : (vector<address>, vector<Proposal>) = validators.into_keys_values();
            let mut index = 0;
            while (index < 11) {
                let proposal = props.borrow(index);
                if (proposal.response) {
                    num_in_favor = num_in_favor + 1;
                };
                index = index + 1;
            };
            let mut wrong_answers = 0;
            if (num_in_favor > 5) {
                wrong_answers = 11 - num_in_favor;
            } else {
                wrong_answers = num_in_favor;
            };

            let right_answers = 11 - wrong_answers;

            // say arbitrarily that everyone puts in 10 sui to query
            // total is 110 sui
            // winners distribute it evenly. 
            // TODO: factor in some percentage of the bet as well (0.5%)?
            // TODO: floats not allowed in sui
            let amount_earned =  (wrong_answers * 10) / right_answers;

            index = 0;
            while (index < 11) {
                let proposal = props.remove(index);
                if ((proposal.response && num_in_favor > 5) || (!proposal.response && num_in_favor <= 5)) {
                    // initiate the transfer.
                    let locked_funds = &mut game_data.funds;
                    let payout = coin::take<SUI>(locked_funds, amount_earned, ctx);
                    transfer::public_transfer(payout, proposal.proposer);
                };
                index = index + 1;

                // delete the proposal
                let Proposal {id, proposer: _, oracleId: _, question: _, response: _, query_id: _} = proposal;
                id.delete();
            };
            
            // process the oracle answer.
            if (num_in_favor > 5) {
                process_oracle_answer(betId, game_data, true, ctx);
            } else {
                process_oracle_answer(betId, game_data, false, ctx);
            };

            
            // cleanup
            id.delete();
            props.destroy_empty();
        }
    }

    // END AUSTIN

    //create a new Bet object
    public fun create_bet(game_data: &mut GameData, consenting_address: address,
        question: String, amount: u64,
        odds: u64, 
        game_start_time: u64, game_end_time: u64, user_bet: Coin<SUI>, ctx: &mut TxContext
    ) {
        let creator_address = tx_context::sender(ctx);
        let bet_address = tx_context::fresh_object_address(ctx);
        let bet_id = bet_address.to_id();
        // assert!(tx_context::sender(ctx) == game_data.owner, ECallerNotInstantiator);
        // assert!(coin::value(&user_bet) == amount, EInsufficientBalance);
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
        game_data.all_bets.add(bet_id, new_bet);

        // TODO: emit an event that a bet has been created so that the front-end can list it.
        // TODO: return bet ID
    }

    // delete a bet if it;s not agreed upon
    // TODO: take in a bet id instead of bet because you cannot pass in an immutable reference to an object_owned object. (shared is ok).
    public fun delete_bet(bet: &mut Bet, game_data: &mut GameData, ctx: &mut TxContext) {
        // assert!(dof::exists_(&game_data.id, bet.bet_id));
        assert!(game_data.all_bets.contains(bet.id.to_inner()), EBetNotFound);
        assert!(bet.creator_address == ctx.sender(), 403);
        assert!(!bet.agreed_by_both, 400);

        let locked_funds = &mut game_data.funds;

        // Withdraw staked amount from locked funds
        let payout = coin::take<SUI>(locked_funds, bet.amount_staked_value, ctx);
        transfer::public_transfer(payout, ctx.sender());

        // Remove bet
        bet.is_active = false;
        let Bet {
            id,
            creator_address: _,
            consenting_address: _,
            question: _,
            amount_staked_value: _,
            bet_id: _,
            odds: _,
            agreed_by_both: _,
            game_start_time: _,
            game_end_time: _,
            is_active: _,
        } = game_data.all_bets.remove(bet.id.to_inner());
        object::delete(id);

        // TODO: emit an event that the bet has been deleted so that the front-end knows.
    }

    //second player in instantiated bet agrees to it here
    public fun agree_to_bet(bet: &mut Bet, clock: &Clock, game_data: &mut GameData, coin: Coin<SUI>, ctx: &mut TxContext) {
        let current_time = clock::timestamp_ms(clock);
        assert!(game_data.all_bets.contains(bet.id.to_inner()), EBetNotFound);
        
        //caller is consenting address and bet is not already agreed to
        assert!(bet.consenting_address == ctx.sender(), 403); // 403: Forbidden, not consenting address
        assert!(!bet.agreed_by_both, 400); // 400: Bad Request, bet already agreed upon
        assert!(bet.is_active, 402); //402: Deprecated bet
        assert!(current_time < bet.game_start_time, 408); // 408: Request Timeout, the window for agreeing to the bet has passed
        //consenting player tokens to storage
        
        let betStake = coin::into_balance(coin);
        balance::join(&mut game_data.funds, betStake);
        
        bet.agreed_by_both = true;

        // emit an event so that the front-end knows?
    }

    // handle expiration of a bet agreement window
    public fun handle_expired_bet(bet: &mut Bet, clock: &Clock, game_data: &mut GameData, ctx: &mut TxContext) {
        let current_time = sui::clock::timestamp_ms(clock);
        assert!(game_data.all_bets.contains(bet.id.to_inner()), EBetNotFound);

        // if time past end time and no agreement, remove this bet
        if (current_time >= bet.game_end_time && !bet.agreed_by_both) {
            let locked_funds = &mut game_data.funds;
            let payout = coin::take<SUI>(locked_funds, bet.amount_staked_value, ctx);
            transfer::public_transfer(payout, bet.creator_address);
            bet.is_active = false;
            let Bet {
                id,
                creator_address: _,
                consenting_address: _,
                question: _,
                amount_staked_value: _,
                bet_id: _,
                odds: _,
                agreed_by_both: _,
                game_start_time: _,
                game_end_time: _,
                is_active: _,
            } = game_data.all_bets.remove(bet.id.to_inner());
            object::delete(id);
        }

        // TODO: emit an event so that the front end knows that the bet has been deleted.
    }

    //after game end time, send bet to oracle for winner verification
    public fun send_bet_to_oracle(bet: &mut Bet, clock: &Clock, game_data: &mut GameData, bet_id: ID, ctx: &mut TxContext) {
        assert!(game_data.all_bets.contains(bet.id.to_inner()), EBetNotFound);

        let current_time = clock::timestamp_ms(clock);

        //Only correct creator/second party can call this, and after bet end time
        assert!((ctx.sender() == bet.creator_address || ctx.sender() == bet.consenting_address) &&
                current_time > bet.game_end_time, 403);

        receiveQuery(game_data, bet_id, bet.question, ctx);
    }

    //after oracle finished, get the winner and perform payout
    fun process_oracle_answer(betId: ID, game_data: &mut GameData, oracle_answer: bool, ctx: &mut TxContext) {
        assert!(game_data.all_bets.contains(betId), EBetNotFound);
        // let bet = vector::borrow_mut(&mut game_data.bets, index);
        let bet: &mut Bet = game_data.all_bets.borrow_mut(betId);

        let winner_address = if (oracle_answer) { bet.creator_address } else { bet.consenting_address };
        let locked_funds = &mut game_data.funds;
        let payout = coin::take<SUI>(locked_funds, bet.amount_staked_value, ctx);
        transfer::public_transfer(payout, winner_address);

        bet.is_active = false;
        let Bet {
            id,
            creator_address: _,
            consenting_address: _,
            question: _,
            amount_staked_value: _,
            bet_id: _,
            odds: _,
            agreed_by_both: _,
            game_start_time: _,
            game_end_time: _,
            is_active: _,
        } = game_data.all_bets.remove(betId);
        object::delete(id);
    }