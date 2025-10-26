module suiven::suiven_poap {
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::clock::{Self, Clock};
    use suiven::suiven_admin::VerifierCap;
    use suiven::suiven_tickets::TicketNFT;

    // ========== HATALAR ==========
    // E_TICKET_NOT_USED = 300: POAP sadece kullanılmış biletler için verilebilir

    /// POAPNFT: Etkinliğe katılım kanıtı NFT
    public struct POAPNFT has key, store {
        id: UID,
        event_id: ID,
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

        let (_, event_id, owner, _, _, _) = suiven_tickets::get_ticket_info(ticket);

        let poap = POAPNFT {
            id: object::new(ctx),
            event_id,
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
    public fun get_poap_info(poap: &POAPNFT): (ID, ID, address, u64, vector<u8>) {
        (
            object::uid_to_inner(&poap.id),
            poap.event_id,
            poap.holder,
            poap.issued_ts,
            poap.metadata_uri
        )
    }

    /// POAP sahibini döndürür
    public fun get_poap_holder(poap: &POAPNFT): address {
        poap.holder
    }
}