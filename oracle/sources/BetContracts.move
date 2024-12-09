module game::betting {
    use sui::coin::{Coin, Self};
    use sui::clock::{Clock};
    use std::string::String;
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::vec_map::{Self, VecMap};
    use sui::bag::{Self, Bag};
    use sui::table::{Self, Table};
    use sui::object_table::{Self, ObjectTable};
    use sui::table_vec::{Self, TableVec};
    use sui::event;
    use sui::random::{Random};

    const ENoQueryToValidate: u64 = 11;
    const ECallerNotInstantiator: u64 = 13;
    const EValidationError: u64 = 14;
    const EWrongFundAmount: u64 = 15;
    const ENotBetOwner: u64 = 16;
    const EBetAlreadyInProgress: u64 = 17;
    const EBetNoLongerActive: u64 = 18;
    const EBetNotYetInProgress: u64 = 19;
    const EQueryNotFound: u64 = 20;
    const EInvalidStakeSize: u64 = 21;
    const EInvalidProposalForBet: u64 = 22;
    const EEndTimeBeforeStartTime: u64 = 23;

    const VAL_SIZE: u64 = 3;

    // public struct ApprovedUsers has key, store {
    //     id: UID,
    //     owner: address,
    //     users: vector<address>,
    // }

    public struct InitializationCap has key, store {
        id: UID,
    }

    public struct GameData has key, store {
        id: UID,
        owner: address,
        funds: Balance<SUI>,
        approved_users: Bag,
        all_queries: ObjectTable<ID, Query>,
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
        for_amount: u64,
        bet_id: ID,
        against_amount: u64,
        agreed_by_both: bool,
        //side of creator is the affirmative of whatever the bet says
        //ex: Eagles defeat Seahawks means instantiator is on Eagles win side
        game_start_time: u64,
        game_end_time: u64,
        is_active: bool,
        stake: Balance<SUI>
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
        id: UID,
        betId: ID,
        question: String, 
        creator_address: address,
        consenting_address: address,
        validators: VecMap<address, Proposal>,
        balance: Balance<SUI>,
        index: u64
    }

    // For Emitting Events
    public struct BetCreated has copy, drop {
        bet_id: ID,
        creator: address,
        question: String,
        for_amount: u64,
        against_amount: u64,
        agreed_by_both: bool,
        game_start_time: u64,
        game_end_time: u64,
        active: bool
    }

    public struct BetDeleted has copy, drop {
        bet_id: ID,
        deleter: address
    }

    public struct BetAccepted has copy, drop {
        bet_id: ID,
        acceptor: address
    }

    public struct BetPaidOut has copy, drop {
        bet_id: ID,
        amount: u64,
        winner: address
    }

    // Contract Functions

    // Called on contract initialization. Gives InitializationCap to caller.
    fun init(ctx: &mut TxContext) {
        let init_cap = InitializationCap {
            id: object::new(ctx), 
        };

        transfer::transfer(init_cap, tx_context::sender(ctx));
    }

    // Initializes the contract with the Initialization Cap
    public fun initialize_contract(init_cap: InitializationCap, coin: Coin<SUI>, ctx: &mut TxContext) {
        let game_data = GameData {
            id: object::new(ctx),
            owner: tx_context::sender(ctx),
            funds: coin::into_balance(coin),
            approved_users: bag::new(ctx),
            all_queries: object_table::new<ID, Query>(ctx),
            query_count: 0,
            num_to_query: table::new<u64, ID>(ctx),
            available_nums: table_vec::empty<u64>(ctx)
        };

        let InitializationCap { id } = init_cap;
        object::delete(id);

        transfer::share_object(game_data);
    }

    // TODO: Take a flat fee of every bet so that total_balance actually grows
    public fun withdraw(game_data: &mut GameData, ctx: &mut TxContext) {
        assert!(ctx.sender() == game_data.owner, ECallerNotInstantiator);
        let total_balance = game_data.funds.value();
        let coin = coin::take(&mut game_data.funds, total_balance, ctx);
        transfer::public_transfer(coin, game_data.owner);
    }

    // AUSTIN FUNCTIONS
    /*
        called by the application to send a query up for betting
    */
    fun receiveQuery(game_data: &mut GameData, bet: &Bet, ctx: &mut TxContext) {
        let mut new_query = Query {
            id: object::new(ctx),
            betId: bet.bet_id,
            question: bet.question,
            creator_address: bet.creator_address,
            consenting_address: bet.consenting_address,
            validators: vec_map::empty<address, Proposal>(),
            balance: balance::zero<SUI>(),
            index: 0
        };

        let temp = new_query.id.to_inner();
        let index;
        if (game_data.available_nums.length() == 0) {
            // increment query_count
            game_data.query_count = game_data.query_count + 1;
            game_data.num_to_query.add(game_data.query_count, temp);
            index = game_data.query_count;
        } else {
            // want to keep a vector of available_nums
            let count = game_data.available_nums.pop_back();
            game_data.num_to_query.add(count, temp);
            index = count;
        };

        new_query.index = index;

        game_data.all_queries.add(temp, new_query);
    }
    
    // Make sure you cannot call from another module
    entry fun requestValidate(game_data: &GameData, r: &Random, ctx: &mut TxContext): (ID, ID) {
        let mut i = 1;
        // You get five turns to try to find a suitable query.
        let mut turn = 0;
        let sender = tx_context::sender(ctx);
        let proposal: Proposal;

        assert!(game_data.query_count != 0, ENoQueryToValidate);

        let mut generator = r.new_generator(ctx);

        while (turn < 5) {
            i = generator.generate_u64_in_range(1, game_data.query_count);
            if (!game_data.num_to_query.contains(i)) {
                turn = turn + 1;
                continue 
            };
            let query_id = game_data.num_to_query.borrow(i);
            let query = game_data.all_queries.borrow(*query_id);
            if (query.validators.contains(&sender) || query.consenting_address == sender || query.creator_address == sender) {
                turn = turn + 1;
                continue
            } else {
                break
            }
        };

        assert!(turn < 5, ENoQueryToValidate);
        assert!(i <= game_data.query_count, ENoQueryToValidate);

        let query_id = game_data.num_to_query.borrow(i);
        let query = game_data.all_queries.borrow(*query_id);
        proposal = Proposal {
            id: object::new(ctx),
            proposer: sender,
            oracleId: query.betId,
            question: query.question,
            response: false,
            query_id: *query_id
        };
        let prop_id = proposal.id.to_inner();
        let bet_id = proposal.oracleId;
        transfer::public_transfer(proposal, sender);

        (prop_id, bet_id)
    }

    public fun receiveValidate(game_data: &mut GameData, bet: &mut Bet, mut prop: Proposal, response: bool, coin: Coin<SUI>, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        let prop_query_id = prop.query_id;

        // check that the bet and query exist
        assert!(bet.is_active, EBetNoLongerActive);
        assert!(bet.agreed_by_both, EBetNotYetInProgress);
        assert!(game_data.all_queries.contains(prop.query_id), EQueryNotFound);
        assert!(prop.oracleId == bet.bet_id, EInvalidProposalForBet);

        let mut query = game_data.all_queries.borrow_mut(prop.query_id);

        // check that the sender hasn't already validated this one
        assert!(!query.validators.contains(&sender), EValidationError);
        prop.response = response;
        query.validators.insert(sender, prop);

        assert!(coin.value() == 10, EWrongFundAmount);
        let amount_staked = coin::into_balance(coin);
        balance::join(&mut query.balance, amount_staked);
        
        if (query.validators.size() == VAL_SIZE) {
            let mut num_in_favor = 0;

            // deconstruct the query
            let actual_query = game_data.all_queries.remove(prop_query_id);
            let Query {id, betId: _, question: _, creator_address: _, consenting_address: _, validators, mut balance, index} = move actual_query;
            let (_vals, mut props) : (vector<address>, vector<Proposal>) = validators.into_keys_values();
            let mut i = 0;
            while (i < VAL_SIZE) {
                let proposal = props.borrow(i);
                if (proposal.response) {
                    num_in_favor = num_in_favor + 1;
                };
                i = i + 1;
            };
            let wrong_answers;
            let majority = VAL_SIZE / 2;
            if (num_in_favor > majority) {
                wrong_answers = VAL_SIZE - num_in_favor;
            } else {
                wrong_answers = num_in_favor;
            };

            let right_answers = VAL_SIZE - wrong_answers;

            // say arbitrarily that everyone puts in 10 sui to query
            // total is 110 sui
            // winners distribute it evenly. 
            // Note: with three validators, it will always work out, but otherwise, floats will not work.
            let amount_earned =  10 + (wrong_answers * 10) / right_answers;

            i = 0;
            while (i < VAL_SIZE) {
                let proposal = props.remove(0);
                // check to see if they got the correct answer, if so, then initiate a transfer
                if ((proposal.response && num_in_favor > majority) || (!proposal.response && num_in_favor <= majority)) {
                    // initiate the transfer.
                    let payout = coin::take<SUI>(&mut balance, amount_earned, ctx);

                    transfer::public_transfer(payout, proposal.proposer);
                };
                i = i + 1;

                // delete the proposal
                let Proposal {id, proposer: _, oracleId: _, question: _, response: _, query_id: _} = proposal;
                id.delete();
            };
            
            // process the oracle answer.
            if (num_in_favor > majority) {
                process_oracle_answer(game_data, bet, true, ctx);
            } else {
                process_oracle_answer(game_data, bet, false, ctx);
            };

            balance.destroy_zero();
            game_data.num_to_query.remove(index);
            game_data.available_nums.push_back(index);

            // cleanup
            id.delete();
            props.destroy_empty();
        }
    }

    // END AUSTIN

    //create a new Bet object
    public fun create_bet(game_data: &mut GameData,
        question: String, amount: u64,
        against_amount: u64, game_end_time: u64, user_bet: Coin<SUI>, clock: &Clock, ctx: &mut TxContext
    ): ID {
        let creator_address = tx_context::sender(ctx);
        assert!(user_bet.value() == amount, EInvalidStakeSize);
        
        let current_time = clock.timestamp_ms();

        assert!(game_end_time > current_time, EEndTimeBeforeStartTime);

        let amount_staked = coin::into_balance(user_bet);

        let bet_uid = object::new(ctx);
        let bet_id = bet_uid.to_inner();

        //we assume side of creator is whatever the String bet's phrase is
            //example: bet String descriptions should 
            //be phrased as "Eagles will win vs. the Seahawks today", then creator has side 'Eagles win'
        let new_bet = Bet {
            id: bet_uid,
            creator_address,
            consenting_address: @0x00,
            question,
            for_amount: amount,
            bet_id,
            against_amount,
            agreed_by_both: false, // Initially false until second party agrees
            game_start_time: current_time,
            game_end_time,
            is_active: true, // Bet is active but not yet agreed upon
            stake: amount_staked
        };

        transfer::share_object(new_bet);

        event::emit(BetCreated {
            bet_id,
            creator: creator_address,
            question,
            for_amount: amount,
            against_amount,
            agreed_by_both: false,
            game_start_time: current_time,
            game_end_time,
            active: true,
        });

        return bet_id
    }
    
    // delete a bet if it;s not agreed upon
    public fun delete_bet(game_data: &mut GameData, mut bet: Bet, ctx: &mut TxContext) {
        assert!(bet.creator_address == ctx.sender(), ENotBetOwner);
        assert!(!bet.agreed_by_both, EBetAlreadyInProgress);

        // Withdraw staked amount from locked funds
        let payout_amount = bet.for_amount;
        let payout = coin::take<SUI>(&mut bet.stake, payout_amount, ctx);
        transfer::public_transfer(payout, bet.creator_address);

        // Remove bet
        bet.is_active = false;
        let Bet {
            id,
            creator_address: _,
            consenting_address: _,
            question: _,
            for_amount: _,
            bet_id: _,
            against_amount: _,
            agreed_by_both: _,
            game_start_time: _,
            game_end_time: _,
            is_active: _,
            stake
        } = bet;
        
        stake.destroy_zero();
        event::emit(BetDeleted {
            bet_id: id.to_inner(),
            deleter: ctx.sender()
        });

        object::delete(id);
    }

    //second player in instantiated bet agrees to it here
    public fun agree_to_bet(game_data: &mut GameData, bet: &mut Bet, coin: Coin<SUI>, clock: &Clock, ctx: &mut TxContext) {
        let current_time = clock.timestamp_ms();

        //caller is consenting address and bet is not already agreed to
        assert!(bet.creator_address != ctx.sender(), ENotBetOwner); 
        assert!(!bet.agreed_by_both, EBetAlreadyInProgress); 
        assert!(bet.is_active, EBetNoLongerActive); 
        assert!(current_time <= bet.game_end_time, EBetNoLongerActive); 

        assert!(coin.value() == bet.against_amount, EInvalidStakeSize);

        let betStake = coin::into_balance(coin);
        balance::join(&mut bet.stake, betStake);
        
        bet.agreed_by_both = true;
        bet.consenting_address = ctx.sender();

        event::emit(BetAccepted {
            bet_id: bet.bet_id,
            acceptor: ctx.sender()
        });
    }

    // handle expiration of a bet agreement window
    public fun handle_expired_bet(game_data: &mut GameData, mut bet: Bet, clock: &Clock, ctx: &mut TxContext) {
        let current_time = clock.timestamp_ms();

        assert!(bet.is_active, EBetNoLongerActive);
        assert!(current_time > bet.game_end_time && !bet.agreed_by_both, EBetAlreadyInProgress);

        let payout_amount = bet.for_amount;
        let payout = coin::take<SUI>(&mut bet.stake, payout_amount, ctx);
        transfer::public_transfer(payout, bet.creator_address);
        bet.is_active = false;
        let Bet {
            id,
            creator_address: _,
            consenting_address: _,
            question: _,
            for_amount: _,
            bet_id: _,
            against_amount: _,
            agreed_by_both: _,
            game_start_time: _,
            game_end_time: _,
            is_active: _,
            stake
        } = bet;
        
        event::emit(BetDeleted {
            bet_id: id.to_inner(),
            deleter: ctx.sender()
        });

        stake.destroy_zero();

        object::delete(id);
    }

    //after game end time, send bet to oracle for winner verification
    public fun send_bet_to_oracle(game_data: &mut GameData, bet: &mut Bet, clock: &Clock, ctx: &mut TxContext) {
        assert!(bet.is_active, EBetNoLongerActive);
        assert!(bet.agreed_by_both, EBetNotYetInProgress);

        let current_time = clock.timestamp_ms();
        assert!(current_time > bet.game_end_time, EBetNotYetInProgress);

        receiveQuery(game_data, bet, ctx);
    }

    //after oracle finished, get the winner and perform payout
    fun process_oracle_answer(game_data: &mut GameData, bet: &mut Bet, oracle_answer: bool, ctx: &mut TxContext) {
        let winner_address = if (oracle_answer) { bet.creator_address } else { bet.consenting_address };
        let payout = coin::take<SUI>(&mut bet.stake, bet.for_amount + bet.against_amount, ctx);
        transfer::public_transfer(payout, winner_address);

        bet.is_active = false;

        event::emit(BetPaidOut {
            bet_id: bet.bet_id,
            winner: winner_address,
            amount: bet.for_amount + bet.against_amount
        });
    }

    // Accessors
    public fun creator(bet: &Bet): address {
        bet.creator_address
    }

    public fun consentor(bet: &Bet): address {
        bet.consenting_address
    }

    public fun question(bet: &Bet): String {
        bet.question
    }

    public fun for_amount(bet: &Bet): u64 {
        bet.for_amount
    }

    public fun against_amount(bet: &Bet): u64 {
        bet.against_amount
    }

    public fun agreed(bet: &Bet): bool {
        bet.agreed_by_both
    }

    public fun active(bet: &Bet): bool {
        bet.is_active
    }

    public fun id(prop: &Proposal): ID {
        prop.id.to_inner()
    }

    public fun proposer(prop: &Proposal): address {
        prop.proposer
    }

    public fun oracleId(prop: &Proposal): ID {
        prop.oracleId
    }

    public fun p_question(prop: &Proposal): String {
        prop.question
    }

    public fun response(prop: &Proposal): bool {
        prop.response
    }

    public fun query_id(prop: &Proposal): ID {
        prop.query_id
    }

    public fun test(game_id: &GameData) {
        
    }

    // Helpers for testing
    #[test_only]
    public fun get_and_transfer_initialization_cap_for_testing(ctx: &mut TxContext) {
        let init_cap = InitializationCap {
            id: object::new(ctx), 
        };

        transfer::transfer(init_cap, tx_context::sender(ctx));
    }
}