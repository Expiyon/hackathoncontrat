module suiven::suiven_tickets {
    use sui::event;
    use sui::clock::{Self, Clock};
    use suiven::suiven_events::{Self, Event};
    use suiven::suiven_admin::VerifierCap;

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
        owner: address,
        used: bool,
        metadata_uri: vector<u8>,
        minted_at: u64,
    }

    /// SUI veya FT ödeyerek bilet mint eder
    public fun burn_and_mint(
        event: &mut Event,
        payment_amount: u128,
        metadata_uri: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ): TicketNFT {
        // Kapasite kontrolü
        let (_, _, _, _, _, capacity, sold, price, _, _, _, _) = suiven_events::get_event_info(event);
        assert!(sold < capacity, 204); // E_EVENT_SOLD_OUT
        
        // Ödeme kontrolü
        assert!(payment_amount >= price, 203); // E_INSUFFICIENT_PAYMENT

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
        let (_, _, _, _, _, capacity, sold, _, _, _, _, _) = suiven_events::get_event_info(event);
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
    public fun get_ticket_info(ticket: &TicketNFT): (ID, ID, address, bool, vector<u8>, u64) {
        (
            object::uid_to_inner(&ticket.id),
            ticket.event_id,
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

    /// Entry point: ödeme miktarıyla bilet satın alır ve kullanıcıya yollar
    public entry fun purchase_with_payment(
        event: &mut Event,
        payment_amount: u128,
        metadata_uri: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let ticket = burn_and_mint(
            event,
            payment_amount,
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
}
