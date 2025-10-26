#[test_only]
module suiven::tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::clock::{Self, Clock};
    use suiven::suiven_admin::{Self, AdminCap, OrganizerCap, VerifierCap, TreasuryCap};
    use suiven::suiven_events::{Self, Event};
    use suiven::suiven_tickets::{Self, TicketNFT};
    use suiven::suiven_poap::{Self, POAPNFT};
    use suiven::suiven_token;

    const ADMIN: address = @0xAD;
    const ORGANIZER: address = @0x0123;
    const USER1: address = @0xABCD;
    const VERIFIER: address = @0xVERF;

    // Test 1: Admin init, grant_organizer ve create_event
    #[test]
    fun test_admin_and_create_event() {
        let mut scenario = ts::begin(ADMIN);
        
        // Admin capability oluştur
        {
            let ctx = ts::ctx(&mut scenario);
            let admin_cap = suiven_admin::AdminCap {
                id: object::new(ctx),
            };
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
            
            let event = suiven_events::create_event(
                &organizer_cap,
                b"walrus://cid123",
                1000000,
                2000000,
                100,
                1000000000, // 1 SUI
                true,
                b"",
                500, // 5% royalty
                true,
                1900000,
                ctx
            );

            // Event bilgilerini kontrol et
            let (_, org, _, _, _, capacity, sold, _, _, _, _, _) = suiven_events::get_event_info(&event);
            assert!(org == ORGANIZER, 1);
            assert!(capacity == 100, 2);
            assert!(sold == 0, 3);

            suiven_events::share_event(event);
            ts::return_to_sender(&scenario, organizer_cap);
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
            let admin_cap = suiven_admin::AdminCap {
                id: object::new(ctx),
            };
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
            
            let event = suiven_events::create_event(
                &organizer_cap,
                b"walrus://cid456",
                1000000,
                2000000,
                10,
                500000000, // 0.5 SUI
                true,
                b"",
                250,
                true,
                1900000,
                ctx
            );

            suiven_events::share_event(event);
            ts::return_to_sender(&scenario, organizer_cap);
        };

        // Kullanıcı bilet satın alır
        ts::next_tx(&mut scenario, USER1);
        {
            let mut event = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);

            let ticket = suiven_tickets::burn_and_mint(
                &mut event,
                500000000, // Yeterli ödeme
                b"walrus://ticket_cid",
                &clock,
                ctx
            );

            // Ticket bilgilerini kontrol et
            let (_, _, owner, used, _, _) = suiven_tickets::get_ticket_info(&ticket);
            assert!(owner == USER1, 4);
            assert!(!used, 5);

            // Sold sayısını kontrol et
            let (_, _, _, _, _, _, sold, _, _, _, _, _) = suiven_events::get_event_info(&event);
            assert!(sold == 1, 6);

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
            let admin_cap = suiven_admin::AdminCap {
                id: object::new(ctx),
            };
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
            
            let event = suiven_events::create_event(
                &organizer_cap,
                b"walrus://holder_event",
                1000000,
                2000000,
                50,
                0,
                false,
                b"HOLDER_TOKEN",
                100,
                true,
                1900000,
                ctx
            );

            suiven_events::share_event(event);
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

            assert!(!suiven_tickets::is_ticket_used(&ticket), 7);
            
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
            let admin_cap = suiven_admin::AdminCap {
                id: object::new(ctx),
            };
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
            
            let event = suiven_events::create_event(
                &organizer_cap,
                b"walrus://transfer_test",
                1000000,
                2000000,
                10,
                100000000,
                true,
                b"",
                500,
                true,
                1900000,
                ctx
            );

            suiven_events::share_event(event);
            ts::return_to_sender(&scenario, organizer_cap);
        };

        // Bilet mint
        ts::next_tx(&mut scenario, USER1);
        {
            let mut event = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);

            let ticket = suiven_tickets::burn_and_mint(
                &