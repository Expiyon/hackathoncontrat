#[test_only]
module suiven::tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use std::string;
    use suiven::suiven_admin::{Self, AdminCap, OrganizerCap, VerifierCap, TreasuryCap};
    use suiven::suiven_events::{Self, Event};
    use suiven::suiven_tickets::{Self, TicketNFT};
    use suiven::suiven_poap::{Self, POAPNFT};
    use suiven::suiven_token;

    const ADMIN: address = @0xAD;
    const ORGANIZER: address = @0x0123;
    const USER1: address = @0xABCD;
    const VERIFIER: address = @0xEF;

    // Test 1: Admin init, grant_organizer ve create_event
    #[test]
    fun test_admin_and_create_event() {
        let mut scenario = ts::begin(ADMIN);

        // Admin capability oluştur
        {
            let ctx = ts::ctx(&mut scenario);
            let admin_cap = suiven_admin::create_admin_cap_for_testing(ctx);
            transfer::public_transfer(admin_cap, ADMIN);
        };

        // Organizer yetkisi ver
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            suiven_admin::grant_organizer(&admin_cap, ORGANIZER, ctx);
            ts::return_to_sender(&scenario, admin_cap);
        };

        // Event oluştur
        ts::next_tx(&mut scenario, ORGANIZER);
        {
            let organizer_cap = ts::take_from_sender<OrganizerCap>(&scenario);
            let ctx = ts::ctx(&mut scenario);

            suiven_events::create_event(
                &organizer_cap,
                string::utf8(b"Test Event"),
                string::utf8(b"walrus://cid123"),
                1000000,
                2000000,
                100,
                1000000000, // 1 SUI
                true,
                string::utf8(b""),
                500, // 5% royalty
                true,
                1900000,
                ctx
            );

            ts::return_to_sender(&scenario, organizer_cap);
        };

        // Event bilgilerini kontrol et
        ts::next_tx(&mut scenario, USER1);
        {
            let event = ts::take_shared<Event>(&scenario);
            let (_, org, _, _, _, _, capacity, sold, _, _, _, _, _) = suiven_events::get_event_info(&event);
            assert!(org == ORGANIZER, 1);
            assert!(capacity == 100, 2);
            assert!(sold == 0, 3);
            ts::return_shared(event);
        };

        ts::end(scenario);
    }

    // Test 2: burn_and_mint - kullanıcı SUI ödeyerek bilet mint eder
    #[test]
    fun test_burn_and_mint() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // Event oluştur
        {
            let ctx = ts::ctx(&mut scenario);
            let admin_cap = suiven_admin::create_admin_cap_for_testing(ctx);
            transfer::public_transfer(admin_cap, ADMIN);
        };

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            suiven_admin::grant_organizer(&admin_cap, ORGANIZER, ctx);
            ts::return_to_sender(&scenario, admin_cap);
        };

        ts::next_tx(&mut scenario, ORGANIZER);
        {
            let organizer_cap = ts::take_from_sender<OrganizerCap>(&scenario);
            let ctx = ts::ctx(&mut scenario);

            suiven_events::create_event(
                &organizer_cap,
                string::utf8(b"Paid Event"),
                string::utf8(b"walrus://cid456"),
                1000000,
                2000000,
                10,
                500000000, // 0.5 SUI
                true,
                string::utf8(b""),
                250,
                true,
                1900000,
                ctx
            );

            ts::return_to_sender(&scenario, organizer_cap);
        };

        // Kullanıcı bilet satın alır
        ts::next_tx(&mut scenario, USER1);
        {
            let mut event = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);

            // SUI coin oluştur
            let payment = coin::mint_for_testing<SUI>(500000000, ctx);

            let ticket = suiven_tickets::burn_and_mint(
                &mut event,
                payment,
                b"walrus://ticket_cid",
                &clock,
                ctx
            );

            // Ticket bilgilerini kontrol et
            let (_, _, _, owner, used, _, _) = suiven_tickets::get_ticket_info(&ticket);
            assert!(owner == USER1, 4);
            assert!(!used, 5);

            // Sold sayısını kontrol et
            let (_, _, _, _, _, _, _, sold, _, _, _, _, _) = suiven_events::get_event_info(&event);
            assert!(sold == 1, 6);

            // Balance kontrolü - 0.5 SUI toplanmalı
            let balance_value = suiven_events::get_balance_value(&event);
            assert!(balance_value == 500000000, 7);

            transfer::public_transfer(ticket, USER1);
            ts::return_shared(event);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // Test 3: mint_if_holds - kullanıcı FT tutuyorsa mint
    #[test]
    fun test_mint_if_holds() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // Setup
        {
            let ctx = ts::ctx(&mut scenario);
            let admin_cap = suiven_admin::create_admin_cap_for_testing(ctx);
            transfer::public_transfer(admin_cap, ADMIN);
        };

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            suiven_admin::grant_organizer(&admin_cap, ORGANIZER, ctx);
            ts::return_to_sender(&scenario, admin_cap);
        };

        ts::next_tx(&mut scenario, ORGANIZER);
        {
            let organizer_cap = ts::take_from_sender<OrganizerCap>(&scenario);
            let ctx = ts::ctx(&mut scenario);

            suiven_events::create_event(
                &organizer_cap,
                string::utf8(b"Holder Event"),
                string::utf8(b"walrus://holder_event"),
                1000000,
                2000000,
                50,
                0,
                false,
                string::utf8(b"HOLDER_TOKEN"),
                100,
                true,
                1900000,
                ctx
            );

            ts::return_to_sender(&scenario, organizer_cap);
        };

        // Kullanıcı holder token'a sahip olduğu için mint yapabilir
        ts::next_tx(&mut scenario, USER1);
        {
            let mut event = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);

            let ticket = suiven_tickets::mint_if_holds(
                &mut event,
                true, // Has required token
                b"walrus://holder_ticket",
                &clock,
                ctx
            );

            assert!(!suiven_tickets::is_ticket_used(&ticket), 8);

            transfer::public_transfer(ticket, USER1);
            ts::return_shared(event);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // Test 4: mark_as_used ve transfer kısıtı
    #[test]
    #[expected_failure(abort_code = 200)] // E_TICKET_USED
    fun test_mark_used_and_transfer_restriction() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 1500000);

        // Setup
        {
            let ctx = ts::ctx(&mut scenario);
            let admin_cap = suiven_admin::create_admin_cap_for_testing(ctx);
            transfer::public_transfer(admin_cap, ADMIN);
        };

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            suiven_admin::grant_organizer(&admin_cap, ORGANIZER, ctx);
            suiven_admin::grant_verifier(&admin_cap, VERIFIER, ctx);
            ts::return_to_sender(&scenario, admin_cap);
        };

        ts::next_tx(&mut scenario, ORGANIZER);
        {
            let organizer_cap = ts::take_from_sender<OrganizerCap>(&scenario);
            let ctx = ts::ctx(&mut scenario);

            suiven_events::create_event(
                &organizer_cap,
                string::utf8(b"Transfer Test Event"),
                string::utf8(b"walrus://transfer_test"),
                1000000,
                2000000,
                10,
                100000000,
                true,
                string::utf8(b""),
                500,
                true,
                1900000,
                ctx
            );

            ts::return_to_sender(&scenario, organizer_cap);
        };

        // Bilet mint
        ts::next_tx(&mut scenario, USER1);
        {
            let mut event = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);

            // SUI coin oluştur
            let payment = coin::mint_for_testing<SUI>(100000000, ctx);

            let mut ticket = suiven_tickets::burn_and_mint(
                &mut event,
                payment,
                b"walrus://ticket2",
                &clock,
                ctx
            );

            ts::return_shared(event);
            transfer::public_transfer(ticket, USER1);
        };

        // Bileti kullanılmış olarak işaretle
        ts::next_tx(&mut scenario, VERIFIER);
        {
            let mut ticket = ts::take_from_address<TicketNFT>(&scenario, USER1);
            let verifier_cap = ts::take_from_sender<VerifierCap>(&scenario);

            suiven_tickets::mark_as_used(&mut ticket, &verifier_cap);

            ts::return_to_sender(&scenario, verifier_cap);
            transfer::public_transfer(ticket, USER1);
        };

        // Kullanılmış bileti transfer etmeye çalış (başarısız olmalı)
        ts::next_tx(&mut scenario, USER1);
        {
            let ticket = ts::take_from_sender<TicketNFT>(&scenario);
            let event = ts::take_shared<Event>(&scenario);

            suiven_tickets::transfer_ticket(ticket, &event, ADMIN, &clock, ts::ctx(&mut scenario));

            ts::return_shared(event);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // Test 5: Admin withdraw funds
    #[test]
    fun test_admin_withdraw_funds() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // Setup admin and organizer
        {
            let ctx = ts::ctx(&mut scenario);
            let admin_cap = suiven_admin::create_admin_cap_for_testing(ctx);
            transfer::public_transfer(admin_cap, ADMIN);
        };

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            suiven_admin::grant_organizer(&admin_cap, ORGANIZER, ctx);
            ts::return_to_sender(&scenario, admin_cap);
        };

        // Create event
        ts::next_tx(&mut scenario, ORGANIZER);
        {
            let organizer_cap = ts::take_from_sender<OrganizerCap>(&scenario);
            let ctx = ts::ctx(&mut scenario);

            suiven_events::create_event(
                &organizer_cap,
                string::utf8(b"Withdraw Test Event"),
                string::utf8(b"walrus://withdraw_test"),
                1000000,
                2000000,
                10,
                1000000000, // 1 SUI
                true,
                string::utf8(b""),
                500,
                true,
                1900000,
                ctx
            );

            ts::return_to_sender(&scenario, organizer_cap);
        };

        // User buys ticket
        ts::next_tx(&mut scenario, USER1);
        {
            let mut event = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);

            let payment = coin::mint_for_testing<SUI>(1000000000, ctx);

            let ticket = suiven_tickets::burn_and_mint(
                &mut event,
                payment,
                b"walrus://ticket3",
                &clock,
                ctx
            );

            // Check balance
            let balance_value = suiven_events::get_balance_value(&event);
            assert!(balance_value == 1000000000, 9);

            transfer::public_transfer(ticket, USER1);
            ts::return_shared(event);
        };

        // Admin withdraws funds
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut event = ts::take_shared<Event>(&scenario);
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let ctx = ts::ctx(&mut scenario);

            suiven_events::withdraw_funds(&admin_cap, &mut event, ctx);

            // Check balance is now zero
            let balance_value = suiven_events::get_balance_value(&event);
            assert!(balance_value == 0, 10);

            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(event);
        };

        // Verify admin received the coin
        ts::next_tx(&mut scenario, ADMIN);
        {
            let coin = ts::take_from_sender<Coin<SUI>>(&scenario);
            assert!(coin::value(&coin) == 1000000000, 11);
            ts::return_to_sender(&scenario, coin);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }
}
