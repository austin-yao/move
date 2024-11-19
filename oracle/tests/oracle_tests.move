#[test_only]
module game::oracle_tests {
    use std::debug;
    use sui::coin::{Coin, Self};
    use sui::sui::SUI;
    use sui::test_scenario::{Self, Scenario};
    use sui::random::{Self, Random};
    use sui::clock::{Self, Clock};

    use game::betting::{Self, InitializationCap, GameData, Bet, Proposal};

    // Tests
    #[test]
    fun test_initialize_contract() {
        let admin = @0x0;
        let mut scenario = test_scenario::begin(admin);
        
        scenario.initialize_contract_for_test(admin);

        scenario.end();
    }

    #[test]
    fun test_create_bet() {
        let admin = @0x0;

        let mut scenario = test_scenario::begin(admin);

        scenario.initialize_contract_for_test(admin);

        scenario.next_tx(admin);
        let bet_id = {
            let mut game_data = scenario.take_shared<GameData>();
            let coin = coin::mint_for_testing<SUI>(10, scenario.ctx());
            let clock = scenario.take_shared<Clock>();

            let bet_id = betting::create_bet(&mut game_data, b"Does this work?".to_string(), 10, 10, 1, coin, &clock, scenario.ctx());

            test_scenario::return_shared(game_data);
            test_scenario::return_shared(clock);
            bet_id
            
        };
        scenario.next_tx(admin);
        {
            let game_data = scenario.take_shared<GameData>();
            let bet = scenario.take_shared_by_id<Bet>(bet_id);
            assert!(bet.creator() == admin, 1);
            assert!(bet.question() == b"Does this work?".to_string(), 2);
            test_scenario::return_shared(bet);
            test_scenario::return_shared(game_data);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = betting::EEndTimeBeforeStartTime)]
    fun test_propose_bet_after_end_time() {
        let admin = @0x0;
        let p1 = @0xF1;

        let mut scenario = test_scenario::begin(admin);

        scenario.initialize_contract_for_test(admin);

        scenario.next_tx(p1);
        {
            let mut clock = scenario.take_shared<Clock>();

            clock.increment_for_testing(2);

            test_scenario::return_shared(clock);
        };

        scenario.next_tx(p1);
        let _bet_id = {
            let mut game_data = scenario.take_shared<GameData>();
            let coin = coin::mint_for_testing<SUI>(10, scenario.ctx());
            let mut clock = scenario.take_shared<Clock>();

            let bet_id = betting::create_bet(&mut game_data, b"Does this work?".to_string(), 10, 10, 1, coin, &clock, scenario.ctx());

            clock.increment_for_testing(2);

            test_scenario::return_shared(game_data);
            test_scenario::return_shared(clock);
            bet_id
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = betting::EInvalidStakeSize)]
    fun test_propose_bet_invalid_stake_size() {
        let admin = @0x0;
        let p1 = @0xF1;

        let mut scenario = test_scenario::begin(admin);

        scenario.initialize_contract_for_test(admin);

        scenario.next_tx(p1);
        let _bet_id = {
            let mut game_data = scenario.take_shared<GameData>();
            let coin = coin::mint_for_testing<SUI>(12, scenario.ctx());
            let clock = scenario.take_shared<Clock>();

            let bet_id = betting::create_bet(&mut game_data, b"Does this work?".to_string(), 10, 10, 1, coin, &clock, scenario.ctx());

            test_scenario::return_shared(game_data);
            test_scenario::return_shared(clock);
            bet_id
        };

        scenario.end();
    }

    #[test]
    fun test_delete_bet() {
        let admin = @0x0;

        let mut scenario = test_scenario::begin(admin);

        scenario.initialize_contract_for_test(admin);

        // Step 1: creating the bet
        scenario.next_tx(admin);
        let bet_id = {
            let mut game_data = scenario.take_shared<GameData>();
            let coin = coin::mint_for_testing<SUI>(10, scenario.ctx());
            let clock = scenario.take_shared<Clock>();

            let bet_id = betting::create_bet(&mut game_data, b"Does this work?".to_string(), 10, 10, 1, coin, &clock, scenario.ctx());
            test_scenario::return_shared(game_data);
            test_scenario::return_shared(clock);
            bet_id
        };

        // Step 2: deleting the bet
        scenario.next_tx(admin);
        {
            let mut game_data = scenario.take_shared<GameData>();
            let bet = scenario.take_shared_by_id<Bet>(bet_id);
            betting::delete_bet(&mut game_data, bet, scenario.ctx());
            test_scenario::return_shared(game_data);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = test_scenario::EObjectNotFound)]
    fun test_delete_bet_twice() {
        let admin = @0x0;

        let mut scenario = test_scenario::begin(admin);

        scenario.initialize_contract_for_test(admin);

        // Step 1: creating the bet
        scenario.next_tx(admin);
        let bet_id = {
            let mut game_data = scenario.take_shared<GameData>();
            let coin = coin::mint_for_testing<SUI>(10, scenario.ctx());
            let clock = scenario.take_shared<Clock>();

            let bet_id = betting::create_bet(&mut game_data, b"Does this work?".to_string(), 10, 10, 1, coin, &clock, scenario.ctx());
            test_scenario::return_shared(game_data);
            test_scenario::return_shared(clock);
            bet_id
        };

        // Step 2: deleting the bet
        scenario.next_tx(admin);
        {
            let mut game_data = scenario.take_shared<GameData>();
            let bet = scenario.take_shared_by_id<Bet>(bet_id);
            betting::delete_bet(&mut game_data, bet, scenario.ctx());
            test_scenario::return_shared(game_data);
        };

        // Step 3: Delete the bet twice.
        scenario.next_tx(admin);
        {
            let mut game_data = scenario.take_shared<GameData>();
            let bet = scenario.take_shared_by_id<Bet>(bet_id);
            betting::delete_bet(&mut game_data, bet, scenario.ctx());
            test_scenario::return_shared(game_data);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = betting::ENotBetOwner)]
    public fun test_delete_bet_not_owner() {
        let admin = @0x0;
        let p1 = @0xF1;

        let mut scenario = test_scenario::begin(admin);

        scenario.initialize_contract_for_test(admin);

        // Step 1: creating the bet
        scenario.next_tx(admin);
        let bet_id = {
            let mut game_data = scenario.take_shared<GameData>();
            let coin = coin::mint_for_testing<SUI>(10, scenario.ctx());
            let clock = scenario.take_shared<Clock>();

            let bet_id = betting::create_bet(&mut game_data, b"Does this work?".to_string(), 10, 10, 1, coin, &clock, scenario.ctx());
            test_scenario::return_shared(game_data);
            test_scenario::return_shared(clock);
            bet_id
        };

        // Step 2: deleting the bet
        scenario.next_tx(p1);
        {
            let mut game_data = scenario.take_shared<GameData>();
            let bet = scenario.take_shared_by_id<Bet>(bet_id);
            betting::delete_bet(&mut game_data, bet, scenario.ctx());
            test_scenario::return_shared(game_data);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = betting::EBetAlreadyInProgress)]
    public fun test_delete_agreed_bet() {
        let admin = @0x0;
        let p1 = @0xF1;
        let p2 = @0xF2;

        let mut scenario = test_scenario::begin(admin);

        scenario.initialize_contract_for_test(admin);

        let bet_id = scenario.create_and_accept_bet_for_test(p1, p2);

        scenario.next_tx(p1);
        {
            let mut game_data = scenario.take_shared<GameData>();
            let bet = scenario.take_shared_by_id<Bet>(bet_id);
            betting::delete_bet(&mut game_data, bet, scenario.ctx());
            test_scenario::return_shared(game_data);
        };

        scenario.end();
    }

    #[test]
    fun test_agree_bet() {
        let admin = @0x0;
        let p1 = @0xF1;
        let p2 = @0xF2;

        let mut scenario = test_scenario::begin(p1);

        scenario.initialize_contract_for_test(admin);

        let bet_id = scenario.create_and_accept_bet_for_test(p1, p2);

        scenario.next_tx(admin);
        {
            let game_data = scenario.take_shared<GameData>();
            let bet = scenario.take_shared_by_id<Bet>(bet_id);

            assert!(bet.creator() == p1, 1);
            assert!(bet.consentor() == p2, 2);
            assert!(bet.agreed(), 3);
            assert!(bet.active(), 4);

            test_scenario::return_shared(game_data);
            test_scenario::return_shared(bet);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = betting::ENotBetOwner)]
    fun test_agree_own_bet() {
        let admin = @0x0;

        let mut scenario = test_scenario::begin(admin);

        scenario.initialize_contract_for_test(admin);

        scenario.create_and_accept_bet_for_test(admin, admin);

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = betting::EBetAlreadyInProgress)]
    fun test_agree_to_agreed_bet() {
        let admin = @0x0;
        let p1 = @0xF1;
        let p2 = @0xF2;

        let mut scenario = test_scenario::begin(p1);

        scenario.initialize_contract_for_test(admin);

        // Step 1: creating the bet
        scenario.next_tx(p1);
        let bet_id = {
            let mut game_data = scenario.take_shared<GameData>();
            let coin = coin::mint_for_testing<SUI>(10, scenario.ctx());
            let mut clock = scenario.take_shared<Clock>();

            let bet_id = betting::create_bet(&mut game_data, b"Does this work?".to_string(), 10, 10, 1, coin, &clock, scenario.ctx());

            clock.increment_for_testing(1);

            test_scenario::return_shared(clock);
            test_scenario::return_shared(game_data);
            bet_id
        };

        scenario.next_tx(p2);
        {
            let mut game_data = scenario.take_shared<GameData>();
            let coin = coin::mint_for_testing<SUI>(10, scenario.ctx());
            let mut bet = scenario.take_shared_by_id<Bet>(bet_id);
            let clock = scenario.take_shared<Clock>();
            
            betting::agree_to_bet(&mut game_data, &mut bet, coin, &clock, scenario.ctx());
            test_scenario::return_shared(game_data);
            test_scenario::return_shared(bet);
            test_scenario::return_shared(clock);
        };

        scenario.next_tx(admin);
        {
            let mut game_data = scenario.take_shared<GameData>();
            let coin = coin::mint_for_testing<SUI>(10, scenario.ctx());
            let mut bet = scenario.take_shared_by_id<Bet>(bet_id);
            let clock = scenario.take_shared<Clock>();
            
            betting::agree_to_bet(&mut game_data, &mut bet, coin, &clock, scenario.ctx());
            test_scenario::return_shared(game_data);
            test_scenario::return_shared(bet);
            test_scenario::return_shared(clock);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = betting::EBetNoLongerActive)]
    fun test_agree_to_bet_after_end() {
        let admin = @0x0;
        let p1 = @0xF1;
        let p2 = @0xF2;

        let mut scenario = test_scenario::begin(admin);
        
        scenario.initialize_contract_for_test(admin);

        scenario.next_tx(p1);
        let bet_id = {
            let mut game_data = scenario.take_shared<GameData>();
            let coin = coin::mint_for_testing<SUI>(10, scenario.ctx());
            let mut clock = scenario.take_shared<Clock>();

            let bet_id = betting::create_bet(&mut game_data, b"Does this work?".to_string(), 10, 10, 1, coin, &clock, scenario.ctx());

            clock.increment_for_testing(2);

            test_scenario::return_shared(game_data);
            test_scenario::return_shared(clock);
            bet_id
        };

        scenario.next_tx(p2);
        {
            let mut game_data = scenario.take_shared<GameData>();
            let coin = coin::mint_for_testing<SUI>(10, scenario.ctx());
            let mut bet = scenario.take_shared_by_id<Bet>(bet_id);
            let mut clock = scenario.take_shared<Clock>();
            
            betting::agree_to_bet(&mut game_data, &mut bet, coin, &clock, scenario.ctx());
            
            test_scenario::return_shared(game_data);
            test_scenario::return_shared(clock);
            test_scenario::return_shared(bet);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = betting::EInvalidStakeSize)]
    fun test_agree_bet_invalid_stake() {
        let admin = @0x0;
        let p1 = @0xF1;

        let mut scenario = test_scenario::begin(admin);

        scenario.initialize_contract_for_test(admin);

        scenario.next_tx(p1);
        let bet_id = {
            let mut game_data = scenario.take_shared<GameData>();
            let coin = coin::mint_for_testing<SUI>(10, scenario.ctx());
            let clock = scenario.take_shared<Clock>();

            let bet_id = betting::create_bet(&mut game_data, b"Does this work?".to_string(), 11, 11, 1, coin, &clock, scenario.ctx());

            test_scenario::return_shared(game_data);
            test_scenario::return_shared(clock);
            bet_id
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = test_scenario::EObjectNotFound)]
    fun test_agree_bet_deleted() {
        let admin = @0x0;
        let p1 = @0xF1;

        let mut scenario = test_scenario::begin(admin);

        scenario.initialize_contract_for_test(admin);

        // Step 1: creating the bet
        scenario.next_tx(admin);
        let bet_id = {
            let mut game_data = scenario.take_shared<GameData>();
            let coin = coin::mint_for_testing<SUI>(10, scenario.ctx());
            let clock = scenario.take_shared<Clock>();

            let bet_id = betting::create_bet(&mut game_data, b"Does this work?".to_string(), 10, 10, 1, coin, &clock, scenario.ctx());
            test_scenario::return_shared(game_data);
            test_scenario::return_shared(clock);
            bet_id
        };

        // Step 2: deleting the bet
        scenario.next_tx(admin);
        {
            let mut game_data = scenario.take_shared<GameData>();
            let bet = scenario.take_shared_by_id<Bet>(bet_id);
            betting::delete_bet(&mut game_data, bet, scenario.ctx());
            test_scenario::return_shared(game_data);
        };

        // Step 3: Try to accept the bet
        scenario.next_tx(p1);
        {
            let mut game_data = scenario.take_shared<GameData>();
            let coin = coin::mint_for_testing<SUI>(10, scenario.ctx());
            let mut bet = scenario.take_shared_by_id<Bet>(bet_id);
            let clock = scenario.take_shared<Clock>();
            
            betting::agree_to_bet(&mut game_data, &mut bet, coin, &clock, scenario.ctx());
            
            test_scenario::return_shared(game_data);
            test_scenario::return_shared(clock);
            test_scenario::return_shared(bet);
        };
        
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = test_scenario::EObjectNotFound)]
    fun test_handle_expired_bet() {
        let admin = @0x0;
        let p1 = @0xF1;

        let mut scenario = test_scenario::begin(admin);

        scenario.initialize_contract_for_test(admin);

        // Create the bet
        scenario.next_tx(p1);
        let bet_id = {
            let mut game_data = scenario.take_shared<GameData>();
            let coin = coin::mint_for_testing<SUI>(10, scenario.ctx());
            let mut clock = scenario.take_shared<Clock>();

            let bet_id = betting::create_bet(&mut game_data, b"Does this work?".to_string(), 10, 10, 1, coin, &clock, scenario.ctx());

            clock.increment_for_testing(2);

            test_scenario::return_shared(game_data);
            test_scenario::return_shared(clock);
            bet_id
        };

        scenario.next_tx(p1);
        {
            let mut game_data = scenario.take_shared<GameData>();
            let clock = scenario.take_shared<Clock>();
            let mut bet = scenario.take_shared_by_id<Bet>(bet_id);

            betting::handle_expired_bet(&mut game_data, bet, &clock, scenario.ctx());

            test_scenario::return_shared(game_data);
            test_scenario::return_shared(clock);
        };

        scenario.next_tx(p1);
        {
            let bet = scenario.take_shared_by_id<Bet>(bet_id);
            test_scenario::return_shared(bet);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = betting::EBetNoLongerActive)]
    fun test_handle_expired_bet_no_longer_active() {
        let admin = @0x0;
        let p1 = @0xF1;
        let p2 = @0xF2;

        let prop1 = @0xA1;
        let prop2 = @0xA2;
        let prop3 = @0xA3;

        let mut scenario = test_scenario::begin(admin);

        scenario.initialize_contract_for_test(admin);
        let bet_id = scenario.create_and_accept_bet_for_test(p1, p2);
        scenario.send_bet_to_oracle_for_test(bet_id, p1);

        scenario.request_and_submit_proposal_for_test(prop1, true);
        scenario.request_and_submit_proposal_for_test(prop2, true);
        scenario.request_and_submit_proposal_for_test(prop3, true);

        scenario.next_tx(p1);
        {
            let mut game_data = scenario.take_shared<GameData>();
            let clock = scenario.take_shared<Clock>();
            let mut bet = scenario.take_shared_by_id<Bet>(bet_id);

            betting::handle_expired_bet(&mut game_data, bet, &clock, scenario.ctx());

            test_scenario::return_shared(game_data);
            test_scenario::return_shared(clock);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = betting::EBetAlreadyInProgress)]
    fun test_handle_expired_bet_agreed() {
        let admin = @0x0;
        let p1 = @0xF1;
        let p2 = @0xF2;

        let mut scenario = test_scenario::begin(admin);

        scenario.initialize_contract_for_test(admin);
        let bet_id = scenario.create_and_accept_bet_for_test(p1, p2);

        scenario.next_tx(p1);
        {
            let mut game_data = scenario.take_shared<GameData>();
            let clock = scenario.take_shared<Clock>();
            let mut bet = scenario.take_shared_by_id<Bet>(bet_id);

            betting::handle_expired_bet(&mut game_data, bet, &clock, scenario.ctx());

            test_scenario::return_shared(game_data);
            test_scenario::return_shared(clock);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = betting::EBetNoLongerActive)]
    fun test_send_bet_to_oracle_bet_not_active() {
        let admin = @0x0;
        let p1 = @0xF1;
        let p2 = @0xF2;

        let prop1 = @0xA1;
        let prop2 = @0xA2;
        let prop3 = @0xA3;

        let mut scenario = test_scenario::begin(admin);
        scenario.initialize_contract_for_test(admin);
        let bet_id = scenario.create_and_accept_bet_for_test(p1, p2);
        scenario.send_bet_to_oracle_for_test(bet_id, p1);

        scenario.request_and_submit_proposal_for_test(prop1, true);
        scenario.request_and_submit_proposal_for_test(prop2, true);
        scenario.request_and_submit_proposal_for_test(prop3, true);

        scenario.next_tx(p1);
        {
            let mut game_data = scenario.take_shared<GameData>();
            let mut bet = scenario.take_shared_by_id<Bet>(bet_id);
            let clock = scenario.take_shared<Clock>();

            betting::send_bet_to_oracle(&mut game_data, &mut bet, &clock, scenario.ctx());

            test_scenario::return_shared(game_data);
            test_scenario::return_shared(clock);
            test_scenario::return_shared(bet);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = betting::EBetNotYetInProgress)]
    fun test_send_bet_to_oracle_not_accepted() {
        let admin = @0x0;
        let p1 = @0xF1;

        let mut scenario = test_scenario::begin(admin);
        scenario.initialize_contract_for_test(admin);
        
        scenario.next_tx(p1);
        let bet_id = {
            let mut game_data = scenario.take_shared<GameData>();
            let coin = coin::mint_for_testing<SUI>(10, scenario.ctx());
            let mut clock = scenario.take_shared<Clock>();

            let bet_id = betting::create_bet(&mut game_data, b"Does this work?".to_string(), 10, 10, 1, coin, &clock, scenario.ctx());

            clock.increment_for_testing(1);

            test_scenario::return_shared(game_data);
            test_scenario::return_shared(clock);
            bet_id
        };

        scenario.next_tx(p1);
        {
            let mut game_data = scenario.take_shared<GameData>();
            let mut bet = scenario.take_shared_by_id<Bet>(bet_id);
            let clock = scenario.take_shared<Clock>();

            betting::send_bet_to_oracle(&mut game_data, &mut bet, &clock, scenario.ctx());

            test_scenario::return_shared(game_data);
            test_scenario::return_shared(clock);
            test_scenario::return_shared(bet);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = betting::EBetNotYetInProgress)]
    fun test_send_bet_to_oracle_not_past_end_time() {
        let admin = @0x0;
        let p1 = @0xF1;
        let p2 = @0xF2;

        let mut scenario = test_scenario::begin(admin);
        scenario.initialize_contract_for_test(admin);
        
        scenario.next_tx(p1);
        let bet_id = {
            let mut game_data = scenario.take_shared<GameData>();
            let coin = coin::mint_for_testing<SUI>(10, scenario.ctx());
            let mut clock = scenario.take_shared<Clock>();

            let bet_id = betting::create_bet(&mut game_data, b"Does this work?".to_string(), 10, 10, 5, coin, &clock, scenario.ctx());

            clock.increment_for_testing(1);

            test_scenario::return_shared(game_data);
            test_scenario::return_shared(clock);
            bet_id
        };

        scenario.next_tx(p2);
        {
            let mut game_data = scenario.take_shared<GameData>();
            let coin = coin::mint_for_testing<SUI>(10, scenario.ctx());
            let mut bet = scenario.take_shared_by_id<Bet>(bet_id);
            let mut clock = scenario.take_shared<Clock>();

            betting::agree_to_bet(&mut game_data, &mut bet, coin, &clock, scenario.ctx());

            test_scenario::return_shared(game_data);
            test_scenario::return_shared(clock);
            test_scenario::return_shared(bet);
        };

        scenario.next_tx(p1);
        {
            let mut game_data = scenario.take_shared<GameData>();
            let mut bet = scenario.take_shared_by_id<Bet>(bet_id);
            let clock = scenario.take_shared<Clock>();

            betting::send_bet_to_oracle(&mut game_data, &mut bet, &clock, scenario.ctx());

            test_scenario::return_shared(game_data);
            test_scenario::return_shared(clock);
            test_scenario::return_shared(bet);
        };

        scenario.end();
    }

    #[test]
    fun test_query_proposal() {
        let admin = @0x0;
        let p1 = @0xF1;
        let p2 = @0xF2;
        let prop_player = @0xF3;

        let mut scenario = test_scenario::begin(prop_player);

        scenario.initialize_contract_for_test(admin);

        let bet_id = scenario.create_and_accept_bet_for_test(p1, p2);

        scenario.send_bet_to_oracle_for_test(bet_id, p1);
        
        // Step 4: Requesting a bet to validate
        scenario.next_tx(prop_player);
        {
            let mut game_data = scenario.take_shared<GameData>();
            let random = scenario.take_shared<Random>();
            betting::requestValidate(&mut game_data, &random, scenario.ctx());

            test_scenario::return_shared(game_data);
            test_scenario::return_shared(random);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = betting::ENoQueryToValidate)]
    fun test_validate_own_bet() {
        let admin = @0x0;
        let p1 = @0xF1;
        let p2 = @0xF2;

        let mut scenario = test_scenario::begin(admin);

        scenario.initialize_contract_for_test(admin);

        let bet_id = scenario.create_and_accept_bet_for_test(p1, p2);
        scenario.send_bet_to_oracle_for_test(bet_id, p1);
        scenario.request_and_submit_proposal_for_test(p1, true);
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = betting::ENoQueryToValidate)]
    fun test_no_query_to_accept() {
        let admin = @0x0;
        let prop_player = @0xF3;

        let mut scenario = test_scenario::begin(admin);

        scenario.initialize_contract_for_test(admin);

        scenario.request_and_submit_proposal_for_test(prop_player, true);

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = betting::ENoQueryToValidate)]
    fun test_already_proposed_only_query() {
        let admin = @0x0;
        let p1 = @0xF1;
        let p2 = @0xF2;

        let prop1 = @0xB1;

        let mut scenario = test_scenario::begin(admin);

        scenario.initialize_contract_for_test(admin);

        let bet_id = scenario.create_and_accept_bet_for_test(p1, p2);
        scenario.send_bet_to_oracle_for_test(bet_id, p1);

        scenario.request_and_submit_proposal_for_test(prop1, true);
        scenario.request_and_submit_proposal_for_test(prop1, true);

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = test_scenario::EEmptyInventory)]
    fun test_payout_bet_size_three() {
        let admin = @0x0;
        let p1 = @0xF1;
        let p2 = @0xF2;

        let prop1 = @0xB1;
        let prop2 = @0xB2;
        let prop3 = @0xB3;

        let mut scenario = test_scenario::begin(admin);

        scenario.initialize_contract_for_test(admin);

        let bet_id = scenario.create_and_accept_bet_for_test(p1, p2);
        scenario.send_bet_to_oracle_for_test(bet_id, p1);

        scenario.request_and_submit_proposal_for_test(prop1, true);
        scenario.request_and_submit_proposal_for_test(prop2, false);
        scenario.request_and_submit_proposal_for_test(prop3, true);

        scenario.next_tx(admin);
        {
            let prop1_coin = scenario.take_from_address<Coin<SUI>>(prop1);
            assert!(prop1_coin.value() == 15, 1);

            let prop3_coin = scenario.take_from_address<Coin<SUI>>(prop3);
            assert!(prop3_coin.value() == 15, 2);

            let winnings = scenario.take_from_address<Coin<SUI>>(p1);
            assert!(winnings.value() == 20, 3);

            test_scenario::return_to_address(prop1, prop1_coin);
            test_scenario::return_to_address(prop3, prop3_coin);
            test_scenario::return_to_address(p1, winnings);

            let prop2_coin = scenario.take_from_address<Coin<SUI>>(prop2);
            assert!(prop2_coin.value() == 15, 2);
            test_scenario::return_to_address(prop2, prop2_coin);
        };

        scenario.end();
    }

    #[test]
    fun test_payout_bet_false_response_size_three() {
        let admin = @0x0;
        let p1 = @0xF1;
        let p2 = @0xF2;

        let prop1 = @0xB1;
        let prop2 = @0xB2;
        let prop3 = @0xB3;

        let mut scenario = test_scenario::begin(admin);

        scenario.initialize_contract_for_test(admin);

        let bet_id = scenario.create_and_accept_bet_for_test(p1, p2);
        scenario.send_bet_to_oracle_for_test(bet_id, p1);

        scenario.request_and_submit_proposal_for_test(prop1, false);
        scenario.request_and_submit_proposal_for_test(prop2, true);
        scenario.request_and_submit_proposal_for_test(prop3, false);

        scenario.next_tx(admin);
        {
            let prop1_coin = scenario.take_from_address<Coin<SUI>>(prop1);
            assert!(prop1_coin.value() == 15, 1);

            let prop3_coin = scenario.take_from_address<Coin<SUI>>(prop3);
            assert!(prop3_coin.value() == 15, 2);

            let winnings = scenario.take_from_address<Coin<SUI>>(p2);
            assert!(winnings.value() == 20, 3);

            test_scenario::return_to_address(prop1, prop1_coin);
            test_scenario::return_to_address(prop3, prop3_coin);
            test_scenario::return_to_address(p2, winnings);

            // let prop2_coin = scenario.take_from_address<Coin<SUI>>(prop2);
            // assert!(prop2_coin.value() == 15, 2);
            // test_scenario::return_to_address(prop2, prop2_coin);
        };

        scenario.end();
    }

    #[test]
    fun test_multiple_bets() {
        let admin = @0x0;
        let p1 = @0xF1;
        let p2 = @0xF2;

        let prop1 = @0xB1;
        let prop2 = @0xB2;
        let prop3 = @0xB3;

        let mut scenario = test_scenario::begin(admin);

        scenario.initialize_contract_for_test(admin);
        let bet_id_1 = scenario.create_and_accept_bet_for_test(p1, p2);
        let bet_id_2 = scenario.create_and_accept_bet_for_test(p1, p2);

        scenario.send_bet_to_oracle_for_test(bet_id_1, p1);
        scenario.send_bet_to_oracle_for_test(bet_id_2, p1);

        scenario.request_and_submit_proposal_for_test(prop1, true);
        scenario.request_and_submit_proposal_for_test(prop1, true);
        scenario.request_and_submit_proposal_for_test(prop2, true);
        scenario.request_and_submit_proposal_for_test(prop2, false);
        scenario.request_and_submit_proposal_for_test(prop3, true);
        scenario.request_and_submit_proposal_for_test(prop3, false);

        
        scenario.next_tx(admin);
        {
            let p1_coin = scenario.take_from_address<Coin<SUI>>(p1);
            let p2_coin = scenario.take_from_address<Coin<SUI>>(p2);
            assert!(p1_coin.value() == 20, 1);
            assert!(p2_coin.value() == 20, 2);
            test_scenario::return_to_address(p1, p1_coin);
            test_scenario::return_to_address(p2, p2_coin);
        };

        scenario.end();
    }

    // ---------------------
    // Helpers
    // ---------------------

    use fun initialize_contract_for_test as Scenario.initialize_contract_for_test;

    fun initialize_contract_for_test(
        scenario: &mut Scenario,
        admin: address
    ) {
        scenario.next_tx(admin);
        {
            betting::get_and_transfer_initialization_cap_for_testing(scenario.ctx());
            random::create_for_testing(scenario.ctx());
            let clock = clock::create_for_testing(scenario.ctx());
            clock::share_for_testing(clock);
        };

        scenario.next_tx(admin);
        {
            let init_cap = scenario.take_from_sender<InitializationCap>();
            let coin = coin::mint_for_testing<SUI>(500, scenario.ctx());

            betting::initialize_contract(init_cap, coin, scenario.ctx());
        }
    }

    use fun create_and_accept_bet_for_test as Scenario.create_and_accept_bet_for_test;

    fun create_and_accept_bet_for_test(scenario: &mut Scenario, p1: address, p2: address): ID {
        scenario.next_tx(p1);
        let bet_id = {
            let mut game_data = scenario.take_shared<GameData>();
            let coin = coin::mint_for_testing<SUI>(10, scenario.ctx());
            let mut clock = scenario.take_shared<Clock>();
            let time = clock.timestamp_ms();

            let bet_id = betting::create_bet(&mut game_data, b"Does this work?".to_string(), 10, 10, time + 1, coin, &clock, scenario.ctx());

            clock.increment_for_testing(1);

            test_scenario::return_shared(game_data);
            test_scenario::return_shared(clock);
            bet_id
        };

        scenario.next_tx(p2);
        {
            let mut game_data = scenario.take_shared<GameData>();
            let coin = coin::mint_for_testing<SUI>(10, scenario.ctx());
            let mut bet = scenario.take_shared_by_id<Bet>(bet_id);
            let mut clock = scenario.take_shared<Clock>();
            
            betting::agree_to_bet(&mut game_data, &mut bet, coin, &clock, scenario.ctx());

            clock.increment_for_testing(1);
            
            test_scenario::return_shared(game_data);
            test_scenario::return_shared(clock);
            test_scenario::return_shared(bet);
        };

        bet_id
    }

    use fun send_bet_to_oracle_for_test as Scenario.send_bet_to_oracle_for_test;

    fun send_bet_to_oracle_for_test(scenario: &mut Scenario, bet_id: ID, user: address) {
        scenario.next_tx(user);
        {
            let mut game_data = scenario.take_shared<GameData>();
            let mut bet = scenario.take_shared_by_id<Bet>(bet_id);
            let mut clock = scenario.take_shared<Clock>();
            betting::send_bet_to_oracle(&mut game_data, &mut bet, &clock, scenario.ctx());

            clock.increment_for_testing(1);

            test_scenario::return_shared(game_data);
            test_scenario::return_shared(bet);
            test_scenario::return_shared(clock);
        };
    }

    use fun request_and_submit_proposal_for_test as Scenario.request_and_submit_proposal_for_test;

    fun request_and_submit_proposal_for_test(scenario: &mut Scenario, prop_player: address, response: bool) {
        // Step 4: Requesting a bet to validate
        scenario.next_tx(prop_player);
        let bet_id = {
            let mut game_data = scenario.take_shared<GameData>();
            let random = scenario.take_shared<Random>();
            let (_prop_id, bet_id): (ID, ID) = betting::requestValidate(&mut game_data, &random, scenario.ctx());
            test_scenario::return_shared(game_data);
            test_scenario::return_shared(random);

            bet_id
        };

        // Step 5: 
        scenario.next_tx(prop_player);
        {
            let mut game_data = scenario.take_shared<GameData>();
            let proposal: Proposal = scenario.take_from_sender<Proposal>();
            let mut bet = scenario.take_shared_by_id<Bet>(bet_id);
            let coin = coin::mint_for_testing<SUI>(10, scenario.ctx());

            betting::receiveValidate(&mut game_data, &mut bet, proposal, response, coin, scenario.ctx());

            test_scenario::return_shared(game_data);
            test_scenario::return_shared(bet);
        };
    }
}