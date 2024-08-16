module 0x0::BetInstantiation2 {
    use sui::coin::{Coin, Self};
    use sui::clock::{Self, Clock};
    use sui::random;
    use std::string::String;
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::dynamic_object_field::{Self as dof};
    use sui::vec_set::{Self, VecSet};

    const EInsufficientBalance: u64 = 10;
    const ENoQueryToValidate: u64 = 11;
    const EBetNotFound: u64 = 12;
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
        all_queries: VecSet<ID>,
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
            all_queries: vec_set::empty<ID>(),
        };

        let InitializationCap { id } = init_cap;
        object::delete(id);

        // sharing ok because it is only modifiable by methods that we define
        transfer::share_object(game_data);
    }

    // AUSTIN FUNCTIONS
    fun receiveQuery(game_data: &mut GameData, bet_id: ID, question: String, ctx: &mut TxContext) {
        // access the vector of queries
        let new_query = Query {
            id: object::new(ctx),
            betId: bet_id,
            question: question,
            validators: vector::empty<Proposal>(),
        };
        game_data.all_queries.insert(new_query.id.to_inner());
        dof::add(&mut game_data.id, new_query.id.to_inner(), new_query)
    }

    public fun requestValidate(ctx: &mut tx_context::TxContext, game_data: &mut GameData, coin: Coin<SUI>, r: & random::Random): Proposal {
        // introduce randomness later, just find the first bet that we can use.
        let mut queries = game_data.all_queries.into_keys();
        let mut index = 0;
        let size = queries.length();
        let mut desire_id = object::id(game_data);
        while (index < queries.length()) {
            // query_id is an ID refernece how to make it not a reference?
            // because of this, store is not working since references do not have the store ability
            // just remove it
            let query_id = vector::remove(&mut queries, 0);
            let new_query_id = query_id;
            vector::push_back(&mut queries, query_id);
            let query: &mut Query = dof::borrow_mut(&mut game_data.id, new_query_id);
            let mut j = 0;
            let mut flag = false;
            while (j < query.validators.length()) {
                if (vector::borrow_mut(&mut query.validators, j).proposer == tx_context::sender(ctx)) {
                    flag = true;
                    break;
                };
                j = j + 1;
            };
            if (flag) {
                index = index + 1;
            } else {
                desire_id = new_query_id;
                break;
            };
        };
        assert!(index < size, ENoQueryToValidate);
        // TODO: they could lose their stake if the bet settles before they report back with the information?
        let query: &mut Query = dof::borrow_mut(& mut game_data.id, desire_id);
        let amount_staked = coin::into_balance(coin);
        balance::join(&mut game_data.funds, amount_staked);
        let new_proposal = Proposal {
            id: object::new(ctx),
            proposer: tx_context::sender(ctx),
            oracleId: query.betId,
            question: query.question,
            response: false,
            query_id: desire_id,
        };
        game_data.all_queries = vec_set::from_keys(queries);
        new_proposal
    }

    public fun receiveValidate(ctx: &mut tx_context::TxContext, bet: &mut Bet, game_data: &mut GameData, prop: Proposal) {
        assert!(dof::exists_(&game_data.id, prop.query_id), EBetNotFound);

        let query: &mut Query = dof::borrow_mut(&mut game_data.id, prop.query_id);

        vector::push_back(&mut query.validators, prop);

        if (vector::length(&query.validators) == 10) {
            // calculate odds
            let mut num_favor: u64 = 0;
            let numProposals = vector::length(&query.validators);
            let mut index = 0;
            while (index < numProposals) {
                let proposal = vector::borrow(&query.validators, index);
                if (proposal.response) {
                    num_favor = num_favor + 1;
                };
                index = index + 1;
            };
            let mut wrong_answers = 0;
            if (num_favor > 5) {
                // everyone who said no is wrong
                wrong_answers = numProposals - num_favor;
            } else {
                // everyone who said yes is wrong
                wrong_answers = num_favor;
            };
            let right_answers = numProposals - wrong_answers;

            // TODO: they should also get some from the bet in case everyone is right
            let amount_earned = 10 + (wrong_answers * 10) / right_answers;

            // doing the payouts
            index = 0;
            while (index < numProposals) {
                let proposal = vector::borrow(&query.validators, index);
                // right answer
                if ((proposal.response && num_favor > 5) || (!proposal.response && num_favor <= 5)) {
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
        dof::add(&mut game_data.id, bet_id, new_bet)
    }

    // delete a bet if it;s not agreed upon
    public fun delete_bet(ctx: &mut TxContext, bet: &mut Bet, game_data: &mut GameData) {
        assert!(dof::exists_(&game_data.id, bet.bet_id));
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
        } = dof::remove<ID, Bet>(&mut game_data.id, bet.bet_id);
        object::delete(id);
    }

    //second player in instantiated bet agrees to it here
    public fun agree_to_bet(ctx: &mut TxContext, bet: &mut Bet, clock: &Clock, game_data: &mut GameData, coin: Coin<SUI>) {
        let current_time = clock::timestamp_ms(clock);
        assert!(dof::exists_(&game_data.id, bet.bet_id));
        
        //caller is consenting address and bet is not already agreed to
        assert!(bet.consenting_address == ctx.sender(), 403); // 403: Forbidden, not consenting address
        assert!(!bet.agreed_by_both, 400); // 400: Bad Request, bet already agreed upon
        assert!(bet.is_active, 402); //402: Deprecated bet
        assert!(current_time < bet.game_start_time, 408); // 408: Request Timeout, the window for agreeing to the bet has passed
        //consenting player tokens to storage
        
        let betStake = coin::into_balance(coin);
        balance::join(&mut game_data.funds, betStake);
        
        bet.agreed_by_both = true;
    }

    // handle expiration of a bet agreement window
    public fun handle_expired_bet(ctx: &mut TxContext, bet: &mut Bet, clock: &Clock, game_data: &mut GameData) {
        let current_time = sui::clock::timestamp_ms(clock);
        assert!(dof::exists_(&game_data.id, bet.bet_id), 404);

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
            } = dof::remove<ID, Bet>(&mut game_data.id, bet.bet_id);
            object::delete(id);
        }
    }

    //after game end time, send bet to oracle for winner verification
    public fun send_bet_to_oracle(ctx: &mut TxContext, bet: &mut Bet, clock: &Clock, game_data: &mut GameData, bet_id: ID) {
        assert!(dof::exists_(&game_data.id, bet_id), 404);

        let current_time = clock::timestamp_ms(clock);

        //Only correct creator/second party can call this, and after bet end time
        assert!((ctx.sender() == bet.creator_address || ctx.sender() == bet.consenting_address) &&
                current_time > bet.game_end_time, 403);

        receiveQuery(game_data, bet_id, bet.question, ctx);
    }

    //after oracle finished, get the winner and perform payout
    fun process_oracle_answer(ctx: &mut TxContext, betId: ID, game_data: &mut GameData, oracle_answer: bool) {
        assert!(dof::exists_(&game_data.id, betId), 404);
        // let bet = vector::borrow_mut(&mut game_data.bets, index);
        let bet: &mut Bet = dof::borrow_mut(&mut game_data.id, betId);

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
        } = dof::remove<ID, Bet>(&mut game_data.id, bet.bet_id);
        object::delete(id);
    }
}