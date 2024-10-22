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
        payee-approved: bool
    }
)

(define-public (create-escrow (payer principal) (payee principal) (amount uint))
    (begin
        (if (or (is-eq payer payee) (is-eq amount u0))
            (err "Invalid input: Payer and payee must be different, and amount must be greater than zero.")
            (if (is-eq payer tx-sender)
                (begin
                    (map-set escrow-contracts { id: (var-get escrow-counter) }
                             { payer: payer, payee: payee, amount: amount, is-active: true, is-funded: false, payer-approved: false, payee-approved: false })
                    (var-set escrow-counter (+ (var-get escrow-counter) u1))
                    (ok (var-get escrow-counter))
                )
                (err "Only the payer can initiate the escrow.")
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
                            (err "Only the payer or payee can approve the release.")
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
                         (is-eq (get is-funded escrow-data) true))
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
                    (err "Both parties must approve before releasing funds.")
                )
                (err "Escrow contract not found.")
            )
        )
    )
)
