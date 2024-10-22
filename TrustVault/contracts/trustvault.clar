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
        dispute-raised: bool,
        expiration-block: uint
    }
)

;; Define arbitrator with proper principal format
(define-constant arbitrator 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)

(define-public (create-escrow (payer principal) (payee principal) (amount uint) (expiration uint))
    (begin
        (if (or (is-eq payer payee) (is-eq amount u0) (<= expiration block-height))
            (err "Invalid input: Payer and payee must be different, amount must be greater than zero, and expiration must be in the future.")
            (if (is-eq payer tx-sender)
                (begin
                    (map-set escrow-contracts { id: (var-get escrow-counter) }
                             { payer: payer, payee: payee, amount: amount, is-active: true, is-funded: false, payer-approved: false, payee-approved: false, dispute-raised: false, expiration-block: expiration })
                    (var-set escrow-counter (+ (var-get escrow-counter) u1))
                    (ok (var-get escrow-counter))
                )
                (err "Only the payer can initiate the escrow.")
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
