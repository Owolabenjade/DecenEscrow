(define-data-var escrow-counter uint u0)
(define-map escrow-contracts
    { id: uint }
    {
        payer: principal,
        payee: principal,
        amount: uint,
        is-active: bool,
        is-funded: bool,
        payer-approved: bool,
        payee-approved: bool,
        arbitrator-approved: bool,
        dispute-raised: bool,
        expiration-block: uint,
        document-hash: (optional (buff 32)),
        document-timestamp: (optional uint)
    }
)

;; Define arbitrator with proper principal format
(define-constant arbitrator 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)

(define-public (create-escrow (payer principal) (payee principal) (amount uint) (expiration uint) (doc-hash (optional (buff 32))) (timestamp (optional uint)))
    (begin
        ;; Validate basic inputs
        (if (or (is-eq payer payee) 
                (is-eq amount u0) 
                (<= expiration block-height))
            (err "Invalid input: Payer and payee must be different, amount must be greater than zero, and expiration must be in the future.")
            
            ;; Validate tx-sender
            (if (not (is-eq payer tx-sender))
                (err "Only the payer can initiate the escrow.")
                
                ;; Validate document hash and timestamp
                (let (
                    (validated-timestamp (if (is-some timestamp)
                                        (if (> (unwrap-panic timestamp) block-height)
                                            timestamp
                                            none)
                                        none))
                    (validated-hash (if (is-some doc-hash)
                                    (if (is-eq (len (unwrap-panic doc-hash)) u32)
                                        doc-hash
                                        none)
                                    none))
                )
                    ;; Create the escrow contract
                    (begin
                        (map-set escrow-contracts 
                            { id: (var-get escrow-counter) }
                            { payer: payer, 
                              payee: payee, 
                              amount: amount, 
                              is-active: true, 
                              is-funded: false, 
                              payer-approved: false, 
                              payee-approved: false, 
                              arbitrator-approved: false, 
                              dispute-raised: false, 
                              expiration-block: expiration, 
                              document-hash: validated-hash, 
                              document-timestamp: validated-timestamp })
                        (var-set escrow-counter (+ (var-get escrow-counter) u1))
                        (ok (- (var-get escrow-counter) u1))
                    )
                )
            )
        )
    )
)

(define-public (raise-dispute (escrow-id uint))
    (if (>= escrow-id (var-get escrow-counter))
        (err "Invalid escrow ID.")
        (let
            (
                (escrow (map-get? escrow-contracts { id: escrow-id }))
            )
            (match escrow
                escrow-data
                (let
                    (
                        (payer (get payer escrow-data))
                        (payee (get payee escrow-data))
                    )
                    (if (or (is-eq tx-sender payer) (is-eq tx-sender payee))
                        (begin
                            (map-set escrow-contracts { id: escrow-id }
                                     (merge escrow-data { dispute-raised: true }))
                            (ok "Dispute has been raised.")
                        )
                        (err "Only the payer or payee can raise a dispute.")
                    )
                )
                (err "Escrow contract not found.")
            )
        )
    )
)

(define-public (approve-release (escrow-id uint))
    (if (>= escrow-id (var-get escrow-counter))
        (err "Invalid escrow ID.")
        (let
            (
                (escrow (map-get? escrow-contracts { id: escrow-id }))
            )
            (match escrow
                escrow-data
                (let
                    (
                        (payer (get payer escrow-data))
                        (payee (get payee escrow-data))
                    )
                    (if (is-eq tx-sender payer)
                        (begin
                            (map-set escrow-contracts { id: escrow-id }
                                     (merge escrow-data { payer-approved: true }))
                            (ok "Payer has approved the release.")
                        )
                        (if (is-eq tx-sender payee)
                            (begin
                                (map-set escrow-contracts { id: escrow-id }
                                         (merge escrow-data { payee-approved: true }))
                                (ok "Payee has approved the release.")
                            )
                            (if (is-eq tx-sender arbitrator)
                                (begin
                                    (map-set escrow-contracts { id: escrow-id }
                                             (merge escrow-data { arbitrator-approved: true }))
                                    (ok "Arbitrator has approved the release.")
                                )
                                (err "Only the payer, payee, or arbitrator can approve the release.")
                            )
                        )
                    )
                )
                (err "Escrow contract not found.")
            )
        )
    )
)

(define-public (release-funds (escrow-id uint))
    (if (>= escrow-id (var-get escrow-counter))
        (err "Invalid escrow ID.")
        (let
            (
                (escrow (map-get? escrow-contracts { id: escrow-id }))
            )
            (match escrow
                escrow-data
                (if (and (is-eq (get payer-approved escrow-data) true)
                         (is-eq (get payee-approved escrow-data) true)
                         (or (is-eq (get arbitrator-approved escrow-data) true)
                             (is-eq (get dispute-raised escrow-data) false))
                         (is-eq (get is-active escrow-data) true))
                    (let
                        (
                            (amount (get amount escrow-data))
                            (payee (get payee escrow-data))
                        )
                        (if (is-ok (stx-transfer? amount tx-sender payee))
                            (begin
                                (map-set escrow-contracts { id: escrow-id }
                                         (merge escrow-data { is-active: false }))
                                (ok "Funds successfully released.")
                            )
                            (err "STX transfer failed.")
                        )
                    )
                    (err "All parties must approve before releasing funds.")
                )
                (err "Escrow contract not found.")
            )
        )
    )
)

(define-public (resolve-dispute (escrow-id uint) (release-to-payee bool))
    (if (>= escrow-id (var-get escrow-counter))
        (err "Invalid escrow ID.")
        (if (is-eq tx-sender arbitrator)
            (let
                (
                    (escrow (map-get? escrow-contracts { id: escrow-id }))
                )
                (match escrow
                    escrow-data
                    (if (is-eq (get dispute-raised escrow-data) true)
                        (let
                            (
                                (payer (get payer escrow-data))
                                (payee (get payee escrow-data))
                                (amount (get amount escrow-data))
                            )
                            (if release-to-payee
                                (if (is-ok (stx-transfer? amount tx-sender payee))
                                    (begin
                                        (map-set escrow-contracts { id: escrow-id }
                                                 (merge escrow-data { is-active: false }))
                                        (ok "Funds released to payee.")
                                    )
                                    (err "STX transfer to payee failed.")
                                )
                                (if (is-ok (stx-transfer? amount tx-sender payer))
                                    (begin
                                        (map-set escrow-contracts { id: escrow-id }
                                                 (merge escrow-data { is-active: false }))
                                        (ok "Funds returned to payer.")
                                    )
                                    (err "STX transfer to payer failed.")
                                )
                            )
                        )
                        (err "No dispute has been raised for this escrow.")
                    )
                    (err "Escrow contract not found.")
                )
            )
            (err "Only the arbitrator can resolve disputes.")
        )
    )
)

(define-public (time-locked-release (escrow-id uint))
    (if (>= escrow-id (var-get escrow-counter))
        (err "Invalid escrow ID.")
        (let
            (
                (escrow (map-get? escrow-contracts { id: escrow-id }))
            )
            (match escrow
                escrow-data
                (if (and (is-eq (get dispute-raised escrow-data) false)
                         (is-eq (get is-active escrow-data) true)
                         (>= block-height (get expiration-block escrow-data)))
                    (let
                        (
                            (amount (get amount escrow-data))
                            (payee (get payee escrow-data))
                        )
                        (if (is-ok (stx-transfer? amount tx-sender payee))
                            (begin
                                (map-set escrow-contracts { id: escrow-id }
                                         (merge escrow-data { is-active: false }))
                                (ok "Funds released to payee after time-lock expiration.")
                            )
                            (err "STX transfer failed.")
                        )
                    )
                    (err "Time-lock not expired or escrow inactive.")
                )
                (err "Escrow contract not found.")
            )
        )
    )
)

(define-public (cancel-escrow (escrow-id uint))
    (if (>= escrow-id (var-get escrow-counter))
        (err "Invalid escrow ID.")
        (let
            (
                (escrow (map-get? escrow-contracts { id: escrow-id }))
            )
            (match escrow
                escrow-data
                (let
                    (
                        (payer (get payer escrow-data))
                        (is-active (get is-active escrow-data))
                        (is-funded (get is-funded escrow-data))
                    )
                    (if (and (is-eq tx-sender payer) (is-eq is-active true))
                        (begin
                            (if is-funded
                                (let
                                    (
                                        (amount (get amount escrow-data))
                                    )
                                    (if (is-ok (stx-transfer? amount tx-sender payer))
                                        (begin
                                            (map-set escrow-contracts { id: escrow-id }
                                                     (merge escrow-data { is-active: false }))
                                            (ok "Escrow successfully cancelled, funds returned to payer.")
                                        )
                                        (err "STX transfer failed.")
                                    )
                                )
                                (begin
                                    (map-set escrow-contracts { id: escrow-id }
                                             (merge escrow-data { is-active: false }))
                                    (ok "Escrow successfully cancelled.")
                                )
                            )
                        )
                        (err "Only the payer can cancel an active escrow.")
                    )
                )
                (err "Escrow contract not found.")
            )
        )
    )
)

(define-public (verify-document (escrow-id uint) (doc-hash (buff 32)))
    (if (>= escrow-id (var-get escrow-counter))
        (err "Invalid escrow ID.")
        (let
            (
                (escrow (map-get? escrow-contracts { id: escrow-id }))
            )
            (match escrow
                escrow-data
                (let
                    (
                        (stored-hash (get document-hash escrow-data))
                    )
                    (if (is-some stored-hash)
                        (if (is-eq (default-to 0x0000000000000000000000000000000000000000000000000000000000000000 stored-hash) doc-hash)
                            (ok "Document hash matches.")
                            (err "Document hash does not match.")
                        )
                        (err "No document hash stored for this escrow.")
                    )
                )
                (err "Escrow contract not found.")
            )
        )
    )
)

(define-public (add-document-hash (escrow-id uint) (doc-hash (buff 32)) (timestamp uint))
    (if (>= escrow-id (var-get escrow-counter))
        (err "Invalid escrow ID.")
        (let
            (
                (escrow (map-get? escrow-contracts { id: escrow-id }))
            )
            (match escrow
                escrow-data
                (let
                    (
                        (payer (get payer escrow-data))
                    )
                    (if (is-eq tx-sender payer)
                        (begin
                            (map-set escrow-contracts { id: escrow-id }
                                     (merge escrow-data { document-hash: (some doc-hash), document-timestamp: (some timestamp) }))
                            (ok "Document hash and timestamp added successfully.")
                        )
                        (err "Only the payer can add a document hash.")
                    )
                )
                (err "Escrow contract not found.")
            )
        )
    )
)