module suiven::suiven_poap {
    use sui::clock::{Self, Clock};
    use sui::package;
    use sui::display;
    use std::string::{Self, String};
    use suiven::suiven_admin::VerifierCap;
    use suiven::suiven_tickets::TicketNFT;

    // ========== ONE-TIME WITNESS ==========
    public struct SUIVEN_POAP has drop {}

    // ========== HATALAR ==========
    // E_TICKET_NOT_USED = 300: POAP sadece kullanılmış biletler için verilebilir

    /// POAPNFT: Etkinliğe katılım kanıtı NFT
    public struct POAPNFT has key, store {
        id: UID,
        event_id: ID,
        event_name: std::string::String,
        holder: address,
        issued_ts: u64,
        metadata_uri: vector<u8>,
    }

    /// Kullanılmış bilet için POAP mint eder
    public fun mint_poap(
        _verifier: &VerifierCap,
        ticket: &TicketNFT,
        metadata_uri: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ): POAPNFT {
        // Bilet kullanılmış olmalı
        use suiven::suiven_tickets;
        assert!(suiven_tickets::is_ticket_used(ticket), 300); // E_TICKET_NOT_USED

        let (_, event_id, event_name, owner, _, _, _) = suiven_tickets::get_ticket_info(ticket);

        let poap = POAPNFT {
            id: object::new(ctx),
            event_id,
            event_name,
            holder: owner,
            issued_ts: clock::timestamp_ms(clock),
            metadata_uri,
        };

        poap
    }

    /// POAP'ı kullanıcıya transfer eder
    public fun transfer_poap(poap: POAPNFT, to: address) {
        transfer::public_transfer(poap, to);
    }

    /// POAP bilgilerini döndürür
    public fun get_poap_info(poap: &POAPNFT): (ID, ID, std::string::String, address, u64, vector<u8>) {
        (
            object::uid_to_inner(&poap.id),
            poap.event_id,
            poap.event_name,
            poap.holder,
            poap.issued_ts,
            poap.metadata_uri
        )
    }

    /// POAP sahibini döndürür
    public fun get_poap_holder(poap: &POAPNFT): address {
        poap.holder
    }

    /// Module initializer - creates Display for POAPNFT
    fun init(otw: SUIVEN_POAP, ctx: &mut TxContext) {
        let keys = vector[
            string::utf8(b"name"),
            string::utf8(b"description"),
            string::utf8(b"image_url"),
            string::utf8(b"project_url"),
        ];

        let values = vector[
            string::utf8(b"{event_name} - POAP"),
            string::utf8(b"Proof of Attendance Protocol NFT"),
            string::utf8(b"https://ccwpidms8429p4fi.public.blob.vercel-storage.com/icora/user/1761487235908_ycvn73.png"),
            string::utf8(b"https://suiven.io"),
        ];

        let publisher = package::claim(otw, ctx);
        let mut display = display::new_with_fields<POAPNFT>(
            &publisher, keys, values, ctx
        );

        display.update_version();

        transfer::public_transfer(publisher, tx_context::sender(ctx));
        transfer::public_transfer(display, tx_context::sender(ctx));
    }
}