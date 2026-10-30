# Data and trust boundaries

- `users/{uid}`: private name, email, phone, role, location, consent, tutorial state. Role is immutable from clients. Verification/suspension are privileged.
- `publicProfiles/{uid}`: server-maintained name, role, location and verification status; never email or phone.
- `products/{id}`: owner, category, stock available for new orders, unit price in USD, minimum, pickup, images and status. Reserved stock is subtracted transactionally; cancellation restores it once.
- `buyerRequests/{id}`: buyer ownership, quantity/unit, optional target price, destination, due date, status.
- `vehicles/{id}`: owner, capacity/unit, registration, operating locations, cargo, base fee and per-km rate.
- `orders/{id}`: server-owned buyer/supplier/transporter IDs, participants, immutable order snapshot, quantity, subtotal, status, stock reservation marker, payment status, timestamps. Direct client writes denied. Request keys deduplicate retries.
- `quotations/{requestId_supplierId}`: supplier response to a buying request. Acceptance creates an order and closes the request atomically.
- `transportRequests/{orderId}` and `transportQuotes/{requestId_driverId}`: server-owned procurement-linked jobs and delivery quotes. Quote selection assigns one transporter atomically.
- `conversations/{id}/messages/{id}`: participant-only reads and server-mediated text writes. Per-user unread/read timestamps, hidden inbox membership and conversation blocks are server-owned.
- `payments/{orderId}`: external payment reference awaiting reconciliation; admin-only verified states.
- `notifications/{id}`: recipient-only activity feed. Deterministic IDs deduplicate trigger retries. Delivery trigger respects categories and removes invalid tokens.
- `users/{uid}/devices`, `/settings/notifications`, `/savedProducts`: owner-only subcollections.
- `reports`: private support/moderation submissions; admin callable access only.
- `reviews/{orderId_target}`: one buyer review per completed order and supplier/transporter target.
- `auditLogs`: server-only administrator actions with reason and timestamp.

Cancellation is allowed before collection. In-transit/delivered issues become disputes. Only the buyer can confirm receipt. A provider-reported arrival is not buyer confirmation. Payments are independent of order status. Verified refunds require an actual external refund and reconciliation reference.

Image objects are scoped by owner under products/vehicles and limited by size and MIME. Download URLs for public marketplace images are shareable bearer URLs. Do not store identity documents in these locations. Sensitive verification documents need a separate private storage workflow.

User deletion removes the Auth account, private user tree, published listings, listing images and notifications. Order, payment, review and conversation records are retained for counterparties and dispute/accounting obligations. Final retention schedules and privacy text require operator approval before launch.
