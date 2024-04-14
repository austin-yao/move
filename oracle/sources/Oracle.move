module 0x1::Oracle {
    // use std::signer;

    // use std::vector;
    use std::string::String;
    use std::vector;
    use sui::tx_context;
    use sui::object::{Self, ID, UID};
    use sui::coin::{Self, Coin, TreasuryCap, join};
    use sui::random;
    use sui::sui::SUI;

    // use sui::object::{Self, ID, Info};
    // use sui::tx_context::{Self, TxContext};
    // use sui::transfer::{Self};
    
    // // get rid of copy later
    // struct Proposal has store, key {
    //     id: UID,
    //     proposer: address,
    //     oracleId: u64,
    //     // 0 or  1
    //     response: bool,
    // }

    // // // get rid of copy later
    // struct Query has store, key, copy {
    //     id: UID,
    //     // p1: address,
    //     // p2: address,
    //     betId: u64,
    //     question: String, 
    //     validators: vector<Proposal>
    // }

    // // // cannot store anything in the global. 

    // // // for the address of the contract (?) if it exists, we store a vector of oracles
    // // // when we need to do operations on the oracles, we retrieve it from the global storage.

    // // // temporarily returns a new Query
    // public fun receiveQuery(betId: u64, question: String, ctx: &mut tx_context::TxContext): Query {
    //     // access the vector of queries
    //     let newQuery = Query {
    //         id: object::new(ctx),
    //         betId: betId,
    //         question: question,
    //         validators: vector::empty<Proposal>(),
    //     };
    //     // add it to the vector of queries
    //     newQuery
    // }

    // // // should also take in coin, will add in later
    // // // TODO: create a new coin type
    // // // how does the user have r lol
    // public fun requestValidate(ctx: &mut tx_context::TxContext, coin: Coin<SUI>, r: & random::Random): Proposal {
    //     let generator = random::new_generator(r, ctx);
    //     // get size of the vector
    //     // TODO: change this to generate a vector in size
    //     let size = 5;
    //     let index = random::generate_u32_in_range(&mut generator, 1, size);

    //     let queries = vector::empty<Query>();
        
    //     // need to rewrite and look at copy
    //     while (vector::contains(&((*vector::borrow(&queries, index)).validators), &(tx_context::sender(ctx)))) {
    //         index = random::generate_u32_in_range(&mut generator, 1, size);
    //     };
    //         // get query
        
    //     Proposal {
    //         id: object::new(ctx),
    //         proposer: tx_context::sender(ctx),
    //         oracleId: (*vector::borrow(&queries, index)).betId,
    //         response: false,
    //     }
    // }

    // public fun receiveValidate(ctx: &mut tx_context::TxContext, prop: Proposal) {
    //     // add proposal to relevant query
    //     // if (query.numProposals == hyperparameter):
    //         // calculate odds
    //         let num_favor = 0;
    //         // iterate through
    //         // call function
    //         // TODO later: calculate payouts
    // }

}