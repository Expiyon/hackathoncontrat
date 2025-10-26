module suiven::suiven_tickets {
    use sui::event;
    use sui::clock::{Self, Clock};
    use sui::package;
    use sui::display;
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use std::string::{Self, String};
    use suiven::suiven_events::{Self, Event};
    use suiven::suiven_admin::VerifierCap;

    // ========== ONE-TIME WITNESS ==========
    public struct SUIVEN_TICKETS has drop {}

    // ========== EVENTS ==========
    public struct TicketPurchased has copy, drop {
        ticket_id: ID,
        event_id: ID,
        buyer: address,
        minted_at: u64,
    }

    // ========== HATALAR ==========
    // E_TICKET_USED = 200: Bilet zaten kullanılmış
    // E_NOT_TRANSFERABLE = 201: Bu etkinliğin biletleri transfer edilemez
    // E_RESALE_WINDOW_CLOSED = 202: Transfer penceresi kapandı
    // E_INSUFFICIENT_PAYMENT = 203: Yetersiz ödeme
    // E_EVENT_SOLD_OUT = 204: Etkinlik biletleri tükendi

    /// TicketNFT: Etkinlik bileti NFT
    public struct TicketNFT has key, store {
        id: UID,
        event_id: ID,
        event_name: std::string::String,
        owner: address,
        used: bool,
        metadata_uri: vector<u8>,
        minted_at: u64,
    }

    /// SUI ödeyerek bilet mint eder
    public fun burn_and_mint(
        event: &mut Event,
        mut payment: Coin<SUI>,
        metadata_uri: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ): TicketNFT {
        // Kapasite kontrolü
        let (_, _, event_name, _, _, _, capacity, sold, price, _, _, _, _) = suiven_events::get_event_info(event);
        assert!(sold < capacity, 204); // E_EVENT_SOLD_OUT

        // Ödeme kontrolü
        let payment_value = coin::value(&payment);
        assert!((payment_value as u128) >= price, 203); // E_INSUFFICIENT_PAYMENT

        // Ödemeyi al ve etkinlik bakiyesine ekle
        let price_u64 = (price as u64);
        let payment_coin = coin::split(&mut payment, price_u64, ctx);
        let payment_balance = coin::into_balance(payment_coin);
        suiven_events::deposit_payment(event, payment_balance);

        // Fazla ödemeyi geri yolla
        if (coin::value(&payment) > 0) {
            transfer::public_transfer(payment, tx_context::sender(ctx));
        } else {
            coin::destroy_zero(payment);
        };

        // Sold sayısını artır
        suiven_events::increment_sold(event);

        // Ticket NFT oluştur
        let ticket_uid = object::new(ctx);
        let ticket_id = object::uid_to_inner(&ticket_uid);
        let event_id = object::id(event);
        let minted_at = clock::timestamp_ms(clock);
        let buyer = tx_context::sender(ctx);

        let ticket = TicketNFT {
            id: ticket_uid,
            event_id,
            event_name,
            owner: buyer,
            used: false,
            metadata_uri,
            minted_at,
        };

        // Emit ticket purchase event
        event::emit(TicketPurchased {
            ticket_id,
            event_id,
            buyer,
            minted_at,
        });

        ticket
    }

    /// Belirli bir token tutuyorsa bilet mint eder (burn yapmadan)
    public fun mint_if_holds(
        event: &mut Event,
        has_required_token: bool, // Caller bu kontrolü önceden yapar
        metadata_uri: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ): TicketNFT {
        assert!(has_required_token, 203); // E_INSUFFICIENT_PAYMENT

        // Kapasite kontrolü
        let (_, _, event_name, _, _, _, capacity, sold, _, _, _, _, _) = suiven_events::get_event_info(event);
        assert!(sold < capacity, 204); // E_EVENT_SOLD_OUT

        // Sold sayısını artır
        suiven_events::increment_sold(event);

        // Ticket NFT oluştur
        let ticket_uid = object::new(ctx);
        let ticket_id = object::uid_to_inner(&ticket_uid);
        let event_id = object::id(event);
        let minted_at = clock::timestamp_ms(clock);
        let buyer = tx_context::sender(ctx);

        let ticket = TicketNFT {
            id: ticket_uid,
            event_id,
            event_name,
            owner: buyer,
            used: false,
            metadata_uri,
            minted_at,
        };

        // Emit ticket purchase event
        event::emit(TicketPurchased {
            ticket_id,
            event_id,
            buyer,
            minted_at,
        });

        ticket
    }

    /// Bileti kullanılmış olarak işaretler (sadece VerifierCap ile)
    public fun mark_as_used(
        ticket: &mut TicketNFT,
        _verifier: &VerifierCap
    ) {
        ticket.used = true;
    }

    /// Bileti başkasına transfer eder (kurallar dahilinde)
    public fun transfer_ticket(
        ticket: TicketNFT,
        event: &Event,
        to: address,
        clock: &Clock,
        _ctx: &mut TxContext
    ) {
        // Bilet kullanılmış mı kontrolü
        assert!(!ticket.used, 200); // E_TICKET_USED

        // Transfer kuralları kontrolü
        let (transferable, resale_window_end) = suiven_events::get_transfer_rules(event);
        assert!(transferable, 201); // E_NOT_TRANSFERABLE

        let current_time = clock::timestamp_ms(clock);
        assert!(current_time <= resale_window_end, 202); // E_RESALE_WINDOW_CLOSED

        // Royalty hesaplaması burada yapılabilir (basit model)
        // let royalty_bps = suiven_events::get_royalty_bps(event);
        // Gerçek uygulamada: fiyatın bir kısmını organizatöre gönder

        // Transfer işlemi
        transfer::public_transfer(ticket, to);
    }

    /// Bilet bilgilerini döndürür
    public fun get_ticket_info(ticket: &TicketNFT): (ID, ID, std::string::String, address, bool, vector<u8>, u64) {
        (
            object::uid_to_inner(&ticket.id),
            ticket.event_id,
            ticket.event_name,
            ticket.owner,
            ticket.used,
            ticket.metadata_uri,
            ticket.minted_at
        )
    }

    /// Bilet kullanıldı mı kontrol eder
    public fun is_ticket_used(ticket: &TicketNFT): bool {
        ticket.used
    }

    /// Bilet sahibini döndürür
    public fun get_ticket_owner(ticket: &TicketNFT): address {
        ticket.owner
    }

    /// Bileti transfer eder (basit versiyon - kurallar olmadan)
    public fun transfer_ticket_simple(ticket: TicketNFT, to: address) {
        transfer::public_transfer(ticket, to);
    }

    /// Entry point: SUI coin ile bilet satın alır ve kullanıcıya yollar
    public entry fun purchase_with_payment(
        event: &mut Event,
        payment: Coin<SUI>,
        metadata_uri: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let ticket = burn_and_mint(
            event,
            payment,
            metadata_uri,
            clock,
            ctx
        );
        transfer::public_transfer(ticket, tx_context::sender(ctx));
    }

    /// Entry point: belirli bir tokenı tutan kullanıcıya bilet verir
    public entry fun purchase_if_holds_token(
        event: &mut Event,
        has_required_token: bool,
        metadata_uri: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let ticket = mint_if_holds(
            event,
            has_required_token,
            metadata_uri,
            clock,
            ctx
        );
        transfer::public_transfer(ticket, tx_context::sender(ctx));
    }

    /// Module initializer - creates Display for TicketNFT
    fun init(otw: SUIVEN_TICKETS, ctx: &mut TxContext) {
        let keys = vector[
            string::utf8(b"name"),
            string::utf8(b"description"),
            string::utf8(b"image_url"),
            string::utf8(b"project_url"),
        ];

        let values = vector[
            string::utf8(b"{event_name}"),
            string::utf8(b"Event Ticket NFT"),
            string::utf8(b"https://ccwpidms8429p4fi.public.blob.vercel-storage.com/icora/user/1761487235908_ycvn73.png"),
            string::utf8(b"https://suiven.io"),
        ];

        let publisher = package::claim(otw, ctx);
        let mut display = display::new_with_fields<TicketNFT>(
            &publisher, keys, values, ctx
        );

        display.update_version();

        transfer::public_transfer(publisher, tx_context::sender(ctx));
        transfer::public_transfer(display, tx_context::sender(ctx));
    }
}
