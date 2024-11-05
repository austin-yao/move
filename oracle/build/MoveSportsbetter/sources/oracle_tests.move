#[test_only]
module game::oracle_tests {
    use std::debug;
    use sui::coin::{Coin, Self};
    use sui::sui::SUI;
    use sui::test_scenario::{Self, Scenario};

    use game::betting::{Self, InitializationCap, GameData, Bet, Proposal, Query};

    // Tests
    #[test]
    fun test_initialize_contract() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);
        
        scenario.initialize_contract_for_test(admin);

        scenario.end();
    }

    #[test]
    fun test_create_bet() {
        let admin = @0xAD;

        let mut scenario = test_scenario::begin(admin);
        let mut bet_id: ID;

        scenario.initialize_contract_for_test(admin);

        scenario.next_tx(admin);
        {
            let mut game_data = scenario.take_shared<GameData>();
            let coin = coin::mint_for_testing<SUI>(10, scenario.ctx());

            bet_id = betting::create_bet(&mut game_data, b"Does this work?".to_string(), 50, 50, 1, 10000, coin, scenario.ctx());
            // how to actually view the bet?
            assert!(game_data.bet_exists(bet_id), 0);
            let bet = game_data.access_bet(bet_id);
            assert!(bet.creator() == admin, 1);
            assert!(bet.question() == b"Does this work?".to_string(), 2);

            test_scenario::return_shared(game_data);
        };

        scenario.end();
    }

    #[test]
    fun test_delete_bet() {
        let admin = @0xAD;

        let mut scenario = test_scenario::begin(admin);
        let mut bet_id: ID;

        scenario.initialize_contract_for_test(admin);

        // Step 1: creating the bet
        scenario.next_tx(admin);
        {
            let mut game_data = scenario.take_shared<GameData>();
            let coin = coin::mint_for_testing<SUI>(10, scenario.ctx());

            bet_id = betting::create_bet(&mut game_data, b"Does this work?".to_string(), 50, 50, 1, 10000, coin, scenario.ctx());
            test_scenario::return_shared(game_data);
        };

        // Step 2: deleting the bet
        scenario.next_tx(admin);
        {
            let mut game_data = scenario.take_shared<GameData>();
            betting::delete_bet(&mut game_data, bet_id, scenario.ctx());
            test_scenario::return_shared(game_data);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = betting::EBetNotFound)]
    fun test_delete_bet_twice() {
        let admin = @0xAD;

        let mut scenario = test_scenario::begin(admin);
        let mut bet_id: ID;

        scenario.initialize_contract_for_test(admin);

        // Step 1: creating the bet
        scenario.next_tx(admin);
        {
            let mut game_data = scenario.take_shared<GameData>();
            let coin = coin::mint_for_testing<SUI>(10, scenario.ctx());

            bet_id = betting::create_bet(&mut game_data, b"Does this work?".to_string(), 50, 50, 1, 10000, coin, scenario.ctx());
            test_scenario::return_shared(game_data);
        };

        // Step 2: deleting the bet
        scenario.next_tx(admin);
        {
            let mut game_data = scenario.take_shared<GameData>();
            betting::delete_bet(&mut game_data, bet_id, scenario.ctx());
            test_scenario::return_shared(game_data);
        };

        // Step 3: Delete the bet twice.
        scenario.next_tx(admin);
        {
            let mut game_data = scenario.take_shared<GameData>();
            betting::delete_bet(&mut game_data, bet_id, scenario.ctx());
            test_scenario::return_shared(game_data);
        };

        scenario.end();
    }

    #[test]
    fun test_accept_bet() {
        let admin = @0xAD;
        let p1 = @0xF1;
        let p2 = @0xF2;
        let mut bet_id: ID;

        let mut scenario = test_scenario::begin(p1);

        scenario.initialize_contract_for_test(admin);

        // Step 1: creating the bet
        scenario.next_tx(p1);
        {
            let mut game_data = scenario.take_shared<GameData>();
            let coin = coin::mint_for_testing<SUI>(10, scenario.ctx());

            bet_id = betting::create_bet(&mut game_data, b"Does this work?".to_string(), 50, 50, 1, 10000, coin, scenario.ctx());
            test_scenario::return_shared(game_data);
        };

        scenario.next_tx(p2);
        {
            let mut game_data = scenario.take_shared<GameData>();
            let coin = coin::mint_for_testing<SUI>(10, scenario.ctx());
            
            betting::agree_to_bet(&mut game_data, bet_id, coin, scenario.ctx());
            test_scenario::return_shared(game_data);
        };

        scenario.end();
    }

    // Helpers
    use fun initialize_contract_for_test as Scenario.initialize_contract_for_test;

    fun initialize_contract_for_test(
        scenario: &mut Scenario,
        admin: address
    ) {
        scenario.next_tx(admin);
        {
            betting::get_and_transfer_initialization_cap_for_testing(scenario.ctx());
        };

        scenario.next_tx(admin);
        {
            let init_cap = scenario.take_from_sender<InitializationCap>();
            let coin = coin::mint_for_testing<SUI>(500, scenario.ctx());

            betting::initialize_contract(init_cap, coin, scenario.ctx());
        }
    }
}