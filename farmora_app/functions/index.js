'use strict';
const {initializeApp} = require('firebase-admin/app');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {getMessaging} = require('firebase-admin/messaging');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onDocumentCreated} = require('firebase-functions/v2/firestore');
const {canTransition, positive} = require('./domain');
initializeApp();
const db = getFirestore();
const options = {region: 'africa-south1', enforceAppCheck: process.env.ENFORCE_APP_CHECK !== 'false'};
const now = () => FieldValue.serverTimestamp();
const fail = (message, code = 'failed-precondition') => { throw new HttpsError(code, message); };
function text(value, max = 500) { if (typeof value !== 'string' || !value.trim() || value.length > max) fail('Invalid text input.', 'invalid-argument'); return value.trim(); }
function id(value) { const v = text(value, 128); if (!/^[a-zA-Z0-9_-]+$/.test(v)) fail('Invalid identifier.', 'invalid-argument'); return v; }
function number(value) { if (!positive(value)) fail('Enter a valid positive amount.', 'invalid-argument'); return value; }
const round = value => Math.round(value * 100) / 100;
function data(snapshot) { if (!snapshot.exists) fail('Record not found.', 'not-found'); return snapshot.data(); }
// Mirrors normalizePhone in lib/core/models.dart so a number resolves to the
// same placeholder login the account was created with.
function normalizePhone(value) {
  if (typeof value !== 'string') return null;
  const raw = value.replace(/[\s().-]/g, '');
  if (!/^\+?\d+$/.test(raw)) return null;
  let digits = raw.replace('+', '');
  if (!raw.startsWith('+')) {
    if (digits.startsWith('00')) digits = digits.slice(2);
    else if (digits.startsWith('0')) digits = '263' + digits.slice(1);
    else if (digits.length === 9) digits = '263' + digits;
  }
  if (digits.startsWith('2630')) digits = '263' + digits.slice(4);
  return digits.length >= 10 && digits.length <= 15 ? digits : null;
}
async function actor(request, role) {
  if (!request.auth) fail('Sign in first.', 'unauthenticated');
  const uid = request.auth.uid, profile = data(await db.doc(`users/${uid}`).get());
  if (profile.suspended || role && profile.role !== role) fail('Action not permitted.', 'permission-denied');
  return {uid, ...profile};
}
async function notify(userId, title, body, category, eventId, target = {}) {
  const ref = eventId ? db.doc(`notifications/${eventId}`) : db.collection('notifications').doc();
  const profile = await db.doc(`users/${userId}`).get();
  if (!profile.exists || profile.data().suspended) return;
  await ref.create({userId, title, body: body ?? '', category, target, read: false, createdAt: now()}).catch(error => { if (error.code !== 6) throw error; });
}
exports.requestOrder = onCall(options, async request => {
  const a = await actor(request, 'buyer'), p = request.data;
  const productRef = db.doc(`products/${id(p.productId)}`), orderRef = db.doc(`orders/${a.uid}_${id(p.requestKey)}`);
  const quantity = number(p.quantity), destination = text(p.destination);
  await db.runTransaction(async tx => {
    const existing = await tx.get(orderRef); if (existing.exists) return;
    const product = data(await tx.get(productRef)); const buyerProfile=data(await tx.get(db.doc('users/'+a.uid))), sellerProfile=data(await tx.get(db.doc('users/'+product.ownerId))); if(buyerProfile.suspended||sellerProfile.suspended)fail('Account unavailable.');
    if (product.status !== 'active' || quantity < product.minimum || quantity > product.quantity || product.ownerId === a.uid) fail('Product or requested quantity is unavailable.');
    tx.create(orderRef, {buyerId: a.uid, supplierId: product.ownerId, participants: [a.uid, product.ownerId], productId: productRef.id, name: product.name, quantity, unit: product.unit, currency:product.currency || 'USD', unitPrice: product.price, subtotal: round(quantity * product.price), pickup: product.location, destination, status: 'requested', paymentStatus: 'pending', stockReserved: false, createdAt: now(), updatedAt: now()});
  });
  return {id: orderRef.id};
});
exports.quoteOrder = onCall(options, async request => {
  const a = await actor(request, 'supplier'), p = request.data, ref = db.doc(`orders/${id(p.orderId)}`), price = number(p.price);
  await db.runTransaction(async tx => { const o = data(await tx.get(ref)); if (o.supplierId !== a.uid) fail('Not your order.', 'permission-denied'); if (o.status !== 'requested') fail('Order already processed.'); tx.update(ref, {unitPrice: price, subtotal: round(price * o.quantity), status: 'quoted', updatedAt: now()}); });
  return {id: ref.id};
});
exports.transitionOrder = onCall(options, async request => {
  const a = await actor(request), p = request.data, ref = db.doc(`orders/${id(p.orderId)}`), next = text(p.next, 30);
  await db.runTransaction(async tx => {
    const o = data(await tx.get(ref));
    const role = o.buyerId === a.uid ? 'buyer' : o.supplierId === a.uid ? 'supplier' : o.transporterId === a.uid ? 'logistics' : null;
    if (!role) fail('Not your order.', 'permission-denied');
    if (o.status === next) return;
    if (!canTransition(o.status, next, role)) fail('Invalid order transition.');
    if (role === 'supplier' && o.transporterId && ['inTransit', 'delivered'].includes(next)) fail('Assigned transporter must update delivery.');
    if (role === 'logistics' && next === 'inTransit' && o.driverAccepted !== true) fail('Accept the assigned job before collection.');
    if(next === 'delivered' && !o.proofPath) fail('Upload proof of delivery first.');
    let productRef, product;
    if (o.productId && (next === 'confirmed' || next === 'cancelled' && o.stockReserved)) {
      productRef = db.doc(`products/${o.productId}`); const snapshot = await tx.get(productRef); product = snapshot.exists ? snapshot.data() : null;
    }
    const transportRef = db.doc(`transportRequests/${ref.id}`);
    const transport = next === 'cancelled' ? await tx.get(transportRef) : null;
    const updates = {status: next, updatedAt: now()};
    if (next === 'confirmed' && o.productId) {
      if (!product || product.status !== 'active' || product.quantity < o.quantity) fail('Insufficient available stock.');
      const remaining = round(product.quantity - o.quantity);
      tx.update(productRef, {quantity: remaining, status: remaining === 0 ? 'soldOut' : 'active', updatedAt: now()}); updates.stockReserved = true;
    }
    if (next === 'cancelled' && o.stockReserved) {
      if (product) tx.update(productRef, {quantity: round(product.quantity + o.quantity), status: product.status === 'soldOut' ? 'active' : product.status, updatedAt: now()});
      updates.stockReserved = false;
    }
    if (next === 'cancelled' && o.paymentStatus === 'paid') updates.refundRequired = true;
    if (transport?.exists) tx.update(transportRef, {status: 'cancelled', updatedAt: now()});
    tx.update(ref, updates);
  });
  return {id: ref.id};
});
exports.submitOffer = onCall(options, async request => {
  const a = await actor(request, 'supplier'), p = request.data, requestId = id(p.requestId), price = number(p.price), ref = db.doc(`quotations/${requestId}_${a.uid}`);
  await db.runTransaction(async tx => { const r = data(await tx.get(db.doc(`buyerRequests/${requestId}`))); const existing = await tx.get(ref); if (r.status !== 'active') fail('Request is closed.'); if (existing.exists && existing.data().status !== 'pending') fail('Offer already processed.'); tx.set(ref, {requestId, buyerId: r.ownerId, supplierId: a.uid, name: r.name, quantity: r.quantity, unit: r.unit, currency:r.currency || 'USD', price, destination: r.location, status: 'pending', createdAt: now()}); });
  return {id: ref.id};
});
exports.acceptOffer = onCall(options, async request => {
  const a = await actor(request, 'buyer'), ref = db.doc(`quotations/${id(request.data.offerId)}`), order = db.doc(`orders/offer_${ref.id}`);
  await db.runTransaction(async tx => {
    const q = data(await tx.get(ref)), existing = await tx.get(order); if (q.buyerId !== a.uid) fail('Not your offer.', 'permission-denied'); if (existing.exists) return;
    const req = db.doc(`buyerRequests/${q.requestId}`), r = data(await tx.get(req)); const supplier = data(await tx.get(db.doc(`users/${q.supplierId}`))); const buyerProfile=data(await tx.get(db.doc('users/'+a.uid))); if(buyerProfile.suspended)fail('Account unavailable.');
    if (q.status !== 'pending' || r.status !== 'active' || supplier.suspended) fail('Offer unavailable.');
    tx.create(order, {buyerId: a.uid, supplierId: q.supplierId, participants: [a.uid, q.supplierId], name: q.name, quantity: q.quantity, unit: q.unit, currency:q.currency || 'USD', unitPrice: q.price, subtotal: round(q.price * q.quantity), pickup: supplier.location, destination: q.destination, status: 'confirmed', paymentStatus: 'pending', stockReserved: false, createdAt: now(), updatedAt: now()});
    tx.update(ref, {status: 'accepted', orderId: order.id}); tx.update(req, {status: 'fulfilled', updatedAt: now()});
  }); return {id: order.id};
});
exports.requestTransport = onCall(options, async request => {
  const a = await actor(request, 'buyer'), orderRef = db.doc(`orders/${id(request.data.orderId)}`), ref = db.doc(`transportRequests/${orderRef.id}`);
  await db.runTransaction(async tx => { const o = data(await tx.get(orderRef)), existing = await tx.get(ref); if (o.buyerId !== a.uid) fail('Not your order.', 'permission-denied'); if (!['confirmed', 'ready'].includes(o.status) || o.transporterId || o.paymentStatus !== 'pending') fail('Transport cannot be requested.'); if (existing.exists) return; tx.create(ref, {orderId: orderRef.id, ownerId: a.uid, name: o.name, pickup: o.pickup, location: o.pickup, destination: o.destination, quantity: o.quantity, unit: o.unit, currency:o.currency || 'USD', status: 'open', createdAt: now()}); }); return {id: ref.id};
});
exports.submitTransportQuote = onCall(options, async request => {
  const a = await actor(request, 'logistics'), p = request.data, requestId = id(p.requestId), amount = number(p.amount), ref = db.doc(`transportQuotes/${requestId}_${a.uid}`);
  const vehicles = await db.collection('vehicles').where('ownerId', '==', a.uid).where('status', '==', 'active').limit(50).get();
  await db.runTransaction(async tx => {
    const r = data(await tx.get(db.doc(`transportRequests/${requestId}`))), existing = await tx.get(ref);
    if (r.status !== 'open') fail('Transport request is no longer open.');
    if (!vehicles.docs.some(v => v.data().unit === r.unit && v.data().quantity >= r.quantity && (v.data().currency || 'USD') === (r.currency || 'USD'))) fail('Register an available vehicle with sufficient capacity in the cargo unit.');
    if (existing.exists && existing.data().status !== 'pending') fail('Quote already processed.');
    tx.set(ref, {requestId, orderId: r.orderId, buyerId: r.ownerId, transporterId: a.uid, amount, currency:r.currency || 'USD', status: 'pending', createdAt: now()});
  }); return {id: ref.id};
});
exports.acceptTransportQuote = onCall(options, async request => {
  const a = await actor(request, 'buyer'), ref = db.doc(`transportQuotes/${id(request.data.quoteId)}`);
  await db.runTransaction(async tx => {
    const q = data(await tx.get(ref)); if (q.buyerId !== a.uid) fail('Not your quote.', 'permission-denied'); if (q.status === 'accepted') return;
    const orderRef = db.doc(`orders/${q.orderId}`), o = data(await tx.get(orderRef)), requestRef = db.doc(`transportRequests/${q.requestId}`), r = data(await tx.get(requestRef));
    const driver = data(await tx.get(db.doc(`users/${q.transporterId}`)));
    if ((q.currency || 'USD') !== (o.currency || 'USD')) fail('Quotation currency does not match the order.');
    if (driver.suspended || q.status !== 'pending' || r.status !== 'open' || o.transporterId || o.paymentStatus !== 'pending' || !['confirmed', 'ready'].includes(o.status)) fail('Transport is no longer available.');
    tx.update(ref, {status: 'accepted'}); tx.update(requestRef, {status: 'assigned', transporterId: q.transporterId}); tx.update(orderRef, {transporterId: q.transporterId, transportFee: q.amount, participants: FieldValue.arrayUnion(q.transporterId), updatedAt: now()});
  }); return {id: ref.id};
});
exports.recordPayment = onCall(options, async request => {
  const a = await actor(request, 'buyer'), ref = db.doc(`orders/${id(request.data.orderId)}`), reference = text(request.data.reference);
  await db.runTransaction(async tx => {
    const o = data(await tx.get(ref)), paymentRef = db.doc(`payments/${ref.id}`), previous = await tx.get(paymentRef);
    if (o.buyerId !== a.uid) fail('Not your order.', 'permission-denied');
    if (!['pending','failed'].includes(o.paymentStatus) || !['confirmed','ready','inTransit','delivered','completed'].includes(o.status)) fail('Payment cannot be submitted.');
    if (previous.exists && previous.data().status !== 'failed') fail('Payment is already being processed.');
    if (previous.exists) tx.create(paymentRef.collection('attempts').doc(), {...previous.data(), archivedAt:now()});
    tx.set(paymentRef,{orderId:ref.id,buyerId:a.uid,supplierId:o.supplierId,reference,amount:round(o.subtotal+(o.transportFee||0)),currency:o.currency||'USD',status:'awaitingVerification',createdAt:now()});
    tx.update(ref,{paymentStatus:'awaitingVerification',updatedAt:now()});
  }); return {id:ref.id};
});
exports.startConversation = onCall(options, async request => {
  const a = await actor(request), p = request.data;
  if (p.collection === 'orders') {
    const recordId = id(p.recordId), recipientId = id(p.recipientId);
    const order = data(await db.doc(`orders/${recordId}`).get());
    if (recipientId === a.uid || !order.participants.includes(a.uid) || !order.participants.includes(recipientId)) fail('Not an order participant.', 'permission-denied');
    const other = data(await db.doc(`users/${recipientId}`).get());
    if (other.suspended) fail('Account unavailable.');
    const participants = [a.uid, recipientId].sort();
    const key = require('node:crypto').createHash('sha256').update(JSON.stringify([recordId, participants])).digest('hex');
    const ref = db.doc(`conversations/order_${key}`);
    await db.runTransaction(async tx => { if (!(await tx.get(ref)).exists) tx.create(ref, {participants, title: order.name, collection: 'orders', recordId, createdAt: now(), updatedAt: now()}); });
    return {id: ref.id};
  }
  if (!['products', 'buyerRequests', 'transportRequests'].includes(p.collection)) fail('Unsupported conversation reference.');
  const recordId = id(p.recordId), record = data(await db.doc(`${p.collection}/${recordId}`).get());
  const requiredRole = {products: 'buyer', buyerRequests: 'supplier', transportRequests: 'logistics'}[p.collection];
  if (a.role !== requiredRole || record.ownerId === a.uid) fail('Conversation not permitted.', 'permission-denied');
  const other = data(await db.doc(`users/${record.ownerId}`).get()); if (other.suspended) fail('Account unavailable.');
  const participants = [a.uid, record.ownerId].sort(), ref = db.doc(`conversations/${p.collection}_${recordId}_${participants.join('_')}`);
  await db.runTransaction(async tx => { const existing = await tx.get(ref); if (!existing.exists) tx.create(ref, {participants, title: record.name, collection: p.collection, recordId, createdAt: now(), updatedAt: now()}); }); return {id: ref.id};
});
exports.sendMessage = onCall(options, async request => {
  const a = await actor(request), ref = db.doc(`conversations/${id(request.data.conversationId)}`);
  const imagePath = request.data.imagePath ? text(request.data.imagePath, 500) : null;
  const message = imagePath && !request.data.text ? '' : text(request.data.text, 4000);
  const messageRef = request.data.requestKey ? ref.collection('messages').doc(id(request.data.requestKey)) : ref.collection('messages').doc();
  const conversation = data(await ref.get());
  if (!conversation.participants.includes(a.uid)) fail('Not a participant.', 'permission-denied');
  if (imagePath) {
    if (!imagePath.startsWith(`chat/${ref.id}/${a.uid}/`) || imagePath.split('/').length !== 4) fail('Invalid attachment location.');
    const [metadata] = await require('firebase-admin/storage').getStorage().bucket().file(imagePath).getMetadata();
    if (metadata.contentType !== 'image/jpeg' || Number(metadata.size) > 5 * 1024 * 1024) fail('Invalid attachment.');
  }
  await db.runTransaction(async tx => {
    const c = data(await tx.get(ref)), existing = await tx.get(messageRef);
    if (!c.participants.includes(a.uid)) fail('Not a participant.', 'permission-denied');
    if (existing.exists) { if (existing.data().senderId !== a.uid) fail('Message identifier already used.'); return; }
    if (c.blockedBy?.length) fail('Messaging is blocked for this conversation.');
    const recipient = c.participants.find(uid => uid !== a.uid);
    const recipientProfile = data(await tx.get(db.doc(`users/${recipient}`)));
    if (recipientProfile.suspended) fail('Account unavailable.');
    tx.create(messageRef, {senderId:a.uid, text:message, ...(imagePath ? {imagePath} : {}), createdAt:now()});
    tx.update(ref, {lastMessage:message || 'Photo', updatedAt:now(), hiddenBy:[], ['unread.'+recipient]:FieldValue.increment(1)});
  }); return {id: messageRef.id};
});
exports.messageNotification = onDocumentCreated({document: 'conversations/{conversationId}/messages/{messageId}', region: options.region}, async event => {
  const m = event.data.data(), c = data(await db.doc(`conversations/${event.params.conversationId}`).get());
  await Promise.all(c.participants.filter(uid => uid !== m.senderId).map(uid => notify(uid, 'New message', 'You have a new Farmora message.', 'messages', `message_${event.params.messageId}_${uid}`, {kind:'chat', id:event.params.conversationId})));
});
exports.orderNotification = onDocumentCreated({document: 'orders/{orderId}', region: options.region}, async event => { const o = event.data.data(); await notify(o.supplierId, 'New procurement request', o.name, 'orders', `order_${event.params.orderId}`, {kind:'order',id:event.params.orderId}); });
exports.offerNotification = onDocumentCreated({document: 'quotations/{quoteId}', region: options.region}, async event => { const q = event.data.data(); await notify(q.buyerId, 'New supplier offer', q.name, 'offers', `offer_${event.params.quoteId}`, {kind:'offers'}); });
exports.transportNotification = onDocumentCreated({document: 'transportQuotes/{quoteId}', region: options.region}, async event => { const q = event.data.data(); await notify(q.buyerId, 'New transport quote', 'Compare delivery quotations in your order.', 'transport', `transport_${event.params.quoteId}`, {kind:'order',id:q.orderId}); });
exports.pushNotification = onDocumentCreated({document: 'notifications/{notificationId}', region: options.region}, async event => {
  const n = event.data.data(), settings = (await db.doc(`users/${n.userId}/settings/notifications`).get()).data() || {};
  if (settings[n.category] === false) return;
  const devices = await db.collection(`users/${n.userId}/devices`).limit(100).get(); if (devices.empty) return;
  const profile = await db.doc(`users/${n.userId}`).get();
  if (!profile.exists || profile.data().suspended) return;
  const result = await getMessaging().sendEachForMulticast({tokens: devices.docs.map(d => d.data().token), notification: {title: n.title, body: n.body}, data:{notificationId:event.params.notificationId,userId:n.userId}});
  await Promise.all(result.responses.map((r, i) => !r.success && ['messaging/invalid-registration-token', 'messaging/registration-token-not-registered'].includes(r.error?.code) ? devices.docs[i].ref.delete() : Promise.resolve()));
});
exports.estimateTransport = onCall(options, async request => {
  const a = await actor(request, 'buyer');
  const p = request.data, product = data(await db.doc(`products/${id(p.productId)}`).get()), destination = text(p.destination), quantity = number(p.quantity);
  if (product.status !== 'active' || quantity < product.minimum || quantity > product.quantity) fail('Quantity is unavailable.');
  // Configure this secret in the function environment, never in a Flutter build.
  const key = process.env.GOOGLE_ROUTES_API_KEY;
  if (!key) return {available: false, reason: 'Routing is not configured. Request a transport quote after confirming your order.'};
  const rateLimit = db.doc(`rateLimits/routes_${a.uid}`), current = Date.now();
  await db.runTransaction(async tx => {
    const usage = (await tx.get(rateLimit)).data() || {};
    const minute = Math.floor(current / 60000), day = Math.floor(current / 86400000);
    const minuteCount = usage.minute === minute ? usage.minuteCount || 0 : 0, dayCount = usage.day === day ? usage.dayCount || 0 : 0;
    if (minuteCount >= 10 || dayCount >= 200) fail('Route estimate limit reached. Wait before retrying or request a provider quote.', 'resource-exhausted');
    tx.set(rateLimit,{minute,day,minuteCount:minuteCount+1,dayCount:dayCount+1,updatedAt:now()});
  });
  const response = await fetch('https://routes.googleapis.com/directions/v2:computeRoutes', {method: 'POST', signal: AbortSignal.timeout(15000), headers: {'Content-Type': 'application/json', 'X-Goog-Api-Key': key, 'X-Goog-FieldMask': 'routes.distanceMeters'}, body: JSON.stringify({origin: {address: product.location}, destination: {address: destination}, travelMode: 'DRIVE', routingPreference: 'TRAFFIC_UNAWARE'})});
  if (!response.ok) fail('Road routing is temporarily unavailable. Request a transport quote.', 'unavailable');
  const result = await response.json(), metres = result.routes?.[0]?.distanceMeters;
  if (!Number.isFinite(metres) || metres < 0) return {available: false, reason: 'No road route found. Request a transport quote.'};
  const vehicles = await db.collection('vehicles').where('status','==','active').limit(100).get();
  const suitable = vehicles.docs.filter(v => v.data().unit === product.unit && v.data().quantity >= quantity && (v.data().currency || 'USD') === (product.currency || 'USD'));
  const {estimate} = require('./domain');
  const estimates = suitable.map(v => ({vehicleId:v.id, transporterId:v.data().ownerId, amount:estimate({roadKm:metres/1000, baseFee:v.data().baseFee, rate:v.data().rate}), name:v.data().name})).sort((a,b) => a.amount-b.amount);
  return {currency:product.currency || 'USD', available: estimates.length > 0, roadKm:metres/1000, estimates:estimates.slice(0,10), reason: estimates.length ? 'Estimate only. Service area, tolls, loading and special handling must be confirmed by the transporter.' : 'No suitable vehicle found. Request a transport quote.'};
});
const {onDocumentUpdated} = require('firebase-functions/v2/firestore');
exports.orderUpdateNotification = onDocumentUpdated({document:'orders/{orderId}',region:options.region}, async event => {
  const before = event.data.before.data(), after = event.data.after.data();
  if (before.status === after.status && before.paymentStatus === after.paymentStatus && before.transporterId === after.transporterId) return;
  await Promise.all(after.participants.map(uid => notify(uid, 'Order updated', `${after.name}: ${after.status}; payment ${after.paymentStatus}`, 'orders', `update_${event.id}_${uid}`, {kind:'order',id:event.params.orderId})));
});
async function admin(request) {
  if (!request.auth || request.auth.token.admin !== true) fail('Administrator access required.', 'permission-denied');
  return request.auth.uid;
}
exports.adminList = onCall(options, async request => {
  await admin(request);
  const collection = request.data.collection;
  if (!['users','products','orders','payments','reports','vehicles','transportRequests','categories','platformSettings','verificationRequests'].includes(collection)) fail('Unsupported collection.');
  let query = db.collection(collection).orderBy('__name__').limit(50);
  if (request.data.after) { const cursor = text(request.data.after, 128); if (cursor.includes('/')) fail('Invalid cursor.'); query = query.startAfter(cursor); }
  const snapshot = await query.get();
  return {records: snapshot.docs.map(d => ({id:d.id,...d.data()})), after: snapshot.docs.at(-1)?.id || null};
});
exports.adminAction = onCall(options, async request => {
  const adminId = await admin(request), p = request.data, recordId = id(p.id), reason = text(p.reason);
  await db.runTransaction(async tx => {
    const auditRef = db.collection('auditLogs').doc();
    if (['featureSupplier','unfeatureSupplier'].includes(p.action)) {
      const ref = db.doc(`users/${recordId}`), profile = data(await tx.get(ref));
      if (profile.role !== 'supplier' || p.action === 'featureSupplier' && (!profile.verified || profile.suspended)) fail('Only active verified suppliers may be featured.');
      tx.update(ref,{featured:p.action === 'featureSupplier',updatedAt:now()});
    } else if (p.action === 'resolveReport') {
      const ref = db.doc(`reports/${recordId}`); data(await tx.get(ref));
      tx.update(ref,{status:'resolved',resolution:reason,resolvedBy:adminId,updatedAt:now()});
    } else if (['approveVerification','rejectVerification'].includes(p.action)) {
      const ref = db.doc(`verificationRequests/${recordId}`), verification = data(await tx.get(ref));
      if (verification.status !== 'pending') fail('Verification has already been reviewed.');
      const profile = db.doc(`users/${verification.ownerId}`); data(await tx.get(profile));
      tx.update(ref, {status:p.action === 'approveVerification' ? 'approved' : 'rejected', reason, reviewedBy:adminId, updatedAt:now()});
      tx.update(profile, {verified:p.action === 'approveVerification', updatedAt:now()});
    } else if (['verify','suspend','reinstate'].includes(p.action)) {
      const ref = db.doc(`users/${recordId}`); data(await tx.get(ref));
      tx.update(ref, p.action === 'verify' ? {verified:true} : {suspended:p.action === 'suspend'});
    } else if (p.action === 'moderateProduct') {
      const ref = db.doc(`products/${recordId}`); data(await tx.get(ref)); tx.update(ref,{status:'paused',moderationReason:reason,updatedAt:now()});
    } else if (['verifyPayment','rejectPayment','refundPayment'].includes(p.action)) {
      const ref = db.doc(`payments/${recordId}`), payment = data(await tx.get(ref)), order = db.doc(`orders/${payment.orderId}`); const orderData=data(await tx.get(order));
      const status = p.action === 'verifyPayment' ? 'paid' : p.action === 'rejectPayment' ? 'failed' : 'refunded';
      if (status === 'refunded' ? payment.status !== 'paid' : payment.status !== 'awaitingVerification') fail('Invalid payment transition.');
      tx.update(ref,{status,reconciledBy:adminId,reconciliationReference:reason,updatedAt:now()}); tx.update(order,{paymentStatus:status,...(status==='refunded'?{refundRequired:false}:status==='paid'&&orderData.status==='cancelled'?{refundRequired:true}:{}),updatedAt:now()});
    } else if (['retryDelivery','reassignDelivery'].includes(p.action)) {
      const ref = db.doc(`orders/${recordId}`), o = data(await tx.get(ref));
      if (o.status !== 'deliveryFailed') fail('Only failed deliveries can be recovered.');
      const transportRef = db.doc(`transportRequests/${recordId}`), transport = await tx.get(transportRef);
      if (p.action === 'reassignDelivery' && o.paymentStatus !== 'pending') fail('Resolve payment and any refund before changing the transporter.');
      tx.update(ref, {status:'ready', proofPath:FieldValue.delete(), recoveryReason:reason, updatedAt:now(), ...(p.action === 'reassignDelivery' ? {transporterId:FieldValue.delete(), transportFee:FieldValue.delete(), driverAccepted:FieldValue.delete(), participants:[o.buyerId,o.supplierId]} : {})});
      if (p.action === 'reassignDelivery' && transport.exists) tx.delete(transportRef);
    } else if (p.action === 'resolveDispute') {
      const ref = db.doc(`orders/${recordId}`), o = data(await tx.get(ref)); if (!['disputed','deliveryFailed'].includes(o.status)) fail('Order is not disputed.');
      if (!['completed','cancelled'].includes(p.outcome)) fail('Invalid dispute outcome.');
      // Returned/perishable goods must be inspected before a supplier restocks them.
      const transportRef = db.doc(`transportRequests/${recordId}`), transport = await tx.get(transportRef);
      if (p.outcome === 'cancelled' && transport.exists) tx.update(transportRef,{status:'cancelled',updatedAt:now()});
      tx.update(ref,{status:p.outcome,resolution:reason,refundRequired:p.outcome === 'cancelled' && o.paymentStatus === 'paid',...(p.outcome === 'cancelled' ? {stockReserved:false,restockReviewRequired:o.stockReserved === true} : {}),updatedAt:now()});
    } else fail('Unsupported action.');
    tx.create(auditRef,{adminId,action:p.action,recordId,reason,createdAt:now()});
  }); return {ok:true};
});
exports.reportRecord = onCall(options, async request => {
  const a = await actor(request), p = request.data;
  if (!['products','buyerRequests','transportRequests','conversations'].includes(p.collection)) fail('Unsupported report.');
  const recordId = id(p.recordId), record = data(await db.doc(`${p.collection}/${recordId}`).get());
  if (p.collection === 'conversations' && !record.participants.includes(a.uid)) fail('Not your conversation.', 'permission-denied');
  const ref = db.collection('reports').doc(); await ref.create({reporterId:a.uid,collection:p.collection,recordId,reason:text(p.reason,2000),status:'open',createdAt:now()}); return {id:ref.id};
});
exports.updateProfile = onCall(options, async request => {
 const a = await actor(request), p = request.data;
 await db.doc(`users/${a.uid}`).update({name:text(p.name,120),phone:text(p.phone,40),location:text(p.location,500),updatedAt:now()}); return {ok:true};
});
exports.setAvatar = onCall(options, async request => {
  const a = await actor(request), path = text(request.data.path,500);
  if (!path.startsWith(`avatars/${a.uid}/`) || path.split('/').length !== 3) fail('Invalid profile photo.');
  const [metadata] = await require('firebase-admin/storage').getStorage().bucket().file(path).getMetadata();
  if (metadata.contentType !== 'image/jpeg' || Number(metadata.size) >= 5 * 1024 * 1024) fail('Invalid profile photo.');
  await db.doc(`users/${a.uid}`).update({avatarPath:path,updatedAt:now()});
  return {ok:true};
});
exports.manageCategory = onCall(options, async request => {
  const adminId = await admin(request), name = text(request.data.name,80);
  if (name.includes('/') || name === '.' || name === '..' || typeof request.data.active !== 'boolean') fail('Invalid category.');
  const reason = text(request.data.reason,500);
  const batch = db.batch();
  batch.set(db.doc(`categories/${name}`), {name,active:request.data.active,updatedAt:now()});
  batch.create(db.collection('auditLogs').doc(), {adminId,action:'manageCategory',name,active:request.data.active,reason,createdAt:now()});
  await batch.commit(); return {ok:true};
});
exports.configureCurrencies = onCall(options, async request => {
  const adminId = await admin(request), currencies = request.data.currencies, reason = text(request.data.reason,500);
  if (!Array.isArray(currencies) || !currencies.includes('USD') || currencies.length > 6 || new Set(currencies).size !== currencies.length || currencies.some(value => !['USD','ZWG','ZAR','BWP','EUR','GBP'].includes(value))) fail('Choose supported currency codes and retain USD.');
  const batch = db.batch();
  batch.set(db.doc('platformSettings/marketplace'), {currencies,updatedAt:now()}, {merge:true});
  batch.create(db.collection('auditLogs').doc(), {adminId,action:'configureCurrencies',currencies,reason,createdAt:now()});
  await batch.commit(); return {ok:true};
});
exports.submitReview = onCall(options, async request => {
 const a = await actor(request, 'buyer'), p = request.data, orderId = id(p.orderId), target = text(p.target,20);
 const order = data(await db.doc(`orders/${orderId}`).get());
 if (order.buyerId !== a.uid || order.status !== 'completed') fail('Only a completed purchase can be reviewed.');
 if (!['supplier','transporter'].includes(target) || target === 'transporter' && !order.transporterId) fail('Invalid review target.');
 if (!Number.isInteger(p.rating) || p.rating < 1 || p.rating > 5) fail('Choose 1 to 5 stars.');
 await db.doc(`reviews/${orderId}_${target}`).create({orderId,buyerId:a.uid,subjectId:target === 'supplier' ? order.supplierId : order.transporterId,rating:p.rating,comment:text(p.comment,2000),createdAt:now()}).catch(e => { if(e.code === 6) fail('You already reviewed this transaction.'); throw e; }); return {ok:true};
});
exports.contactSupport = onCall(options, async request => {
 const a = await actor(request); const ref = db.collection('reports').doc();
 await ref.create({reporterId:a.uid,kind:'support',reason:text(request.data.message,2000),status:'open',createdAt:now()}); return {id:ref.id};
});
// Self-serve password reset for phone accounts: the caller supplies the number
// they signed up with and a new password. This flow does NOT verify ownership
// of the number, so it is throttled to blunt automated abuse. Enabling SMS
// verification later is the way to make it safe against account takeover.
exports.resetPassword = onCall(options, async request => {
  const number = normalizePhone(request.data && request.data.phone);
  if (!number) fail('Enter a valid phone number.', 'invalid-argument');
  const password = request.data.password;
  if (typeof password !== 'string' || password.length < 8 || password.length > 4096) fail('Use a password of at least 8 characters.', 'invalid-argument');
  const throttle = db.doc(`passwordResets/${number}`);
  await db.runTransaction(async tx => {
    const snap = await tx.get(throttle), windowStart = Date.now() - 3600000;
    const hits = ((snap.exists && snap.data().attempts) || []).filter(t => t > windowStart);
    if (hits.length >= 5) fail('Too many reset attempts for this number. Try again later.', 'resource-exhausted');
    tx.set(throttle, {attempts: [...hits, Date.now()]});
  });
  const auth = require('firebase-admin/auth').getAuth();
  let user;
  try { user = await auth.getUserByEmail(`${number}@phone.farmora.invalid`); }
  catch (e) { if (e.code === 'auth/user-not-found') fail('No account uses that phone number.', 'not-found'); throw e; }
  const profile = await db.doc(`users/${user.uid}`).get();
  if (profile.exists && profile.data().suspended) fail('This account is unavailable. Contact support.', 'permission-denied');
  await auth.updateUser(user.uid, {password});
  return {ok: true};
});
exports.deleteAccount = onCall(options, async request => {
 if(!request.auth)fail('Sign in first.','unauthenticated');
 const uid=request.auth.uid;
 if(Date.now()/1000-request.auth.token.auth_time>300)fail('Sign out and sign in again before deleting your account.','unauthenticated');
 await db.runTransaction(async tx=>{
  const job=db.doc(`accountDeletionJobs/${uid}`),existing=await tx.get(job);if(existing.exists)return;
  const profile=db.doc(`users/${uid}`);data(await tx.get(profile));
  const orders=await tx.get(db.collection('orders').where('participants','array-contains',uid));
  if(orders.docs.some(d=>!['completed','cancelled','declined'].includes(d.data().status)||d.data().paymentStatus==='awaitingVerification'||d.data().refundRequired===true))fail('Resolve active orders, payment verification and refunds first.');
  tx.update(profile,{suspended:true,deleting:true});tx.create(job,{uid,status:'pending',createdAt:now()});
 });return {accepted:true};
});
exports.processAccountDeletion = onDocumentCreated({document:'accountDeletionJobs/{uid}',region:options.region,retry:true},async event=>{
 const uid=event.params.uid,job=event.data.ref;
 if((await job.get()).data().status==='completed')return;
 for(const collection of ['products','buyerRequests','vehicles','notifications','verificationRequests']){
  const docs=await db.collection(collection).where(collection==='notifications'?'userId':'ownerId','==',uid).get();
  for(const d of docs.docs)await d.ref.delete();
 }
 const storage=require('firebase-admin/storage').getStorage();
 for(const folder of ['products','vehicles','verification','avatars'])await storage.bucket().deleteFiles({prefix:`${folder}/${uid}/`});
 await db.recursiveDelete(db.doc(`users/${uid}`));
 await require('firebase-admin/auth').getAuth().deleteUser(uid).catch(e=>{if(e.code!=='auth/user-not-found')throw e;});
 await job.update({status:'completed',completedAt:now()});
});

exports.submitVerification = onCall(options, async request => {
  const a = await actor(request), path = text(request.data.path, 500), description = text(request.data.description, 1000);
  if (!path.startsWith(`verification/${a.uid}/`) || path.split('/').length !== 3) fail('Invalid document location.');
  const [metadata] = await require('firebase-admin/storage').getStorage().bucket().file(path).getMetadata();
  if (metadata.contentType !== 'image/jpeg' || Number(metadata.size) >= 5 * 1024 * 1024) fail('Invalid document image.');
  const ref = db.doc(`verificationRequests/${a.uid}`);
  await db.runTransaction(async tx => {
    const existing = await tx.get(ref);
    if (existing.exists && existing.data().status === 'pending') fail('Your documents are already awaiting review.');
    if (a.verified) fail('Your business is already verified.');
    tx.set(ref, {ownerId:a.uid, name:a.name, role:a.role, path, description, status:'pending', createdAt:now(), updatedAt:now()});
  }); return {id:ref.id};
});

async function forEachPage(query, process) {
  let cursor;
  do {
    const page = await (cursor ? query.startAfter(cursor) : query).limit(100).get();
    for (const doc of page.docs) await process(doc);
    cursor = page.size === 100 ? page.docs.at(-1) : null;
  } while (cursor);
}
exports.matchedRequestNotification = onDocumentCreated({document:'buyerRequests/{requestId}', region:options.region, retry:true}, async event => {
  const request = event.data.data();
  if (request.status !== 'active') return;
  const recipients = new Set();
  await forEachPage(db.collection('products').where('category','==',request.category).where('status','==','active').orderBy('__name__'), async doc => {
    const uid = doc.data().ownerId;
    if (recipients.has(uid)) return;
    recipients.add(uid);
    await notify(uid, 'Matching buying request', request.name, 'requests', `request_${event.params.requestId}_${uid}`, {kind:'buyerRequests',id:event.params.requestId});
  });
});
exports.savedPriceNotification = onDocumentUpdated({document:'products/{productId}',region:options.region,retry:true}, async event => {
  const before = event.data.before.data(), after = event.data.after.data();
  if (before.price === after.price || after.status !== 'active') return;
  await forEachPage(db.collectionGroup('savedProducts').where('productId','==',event.params.productId).orderBy('__name__'), async doc => {
    const uid = doc.ref.parent.parent.id;
    await notify(uid, 'Saved product price changed', `${after.name}: ${after.currency || 'USD'} ${after.price} / ${after.unit}`, 'prices', `price_${event.id}_${uid}`, {kind:'products',id:event.params.productId});
  });
});
exports.verificationNotification = onDocumentUpdated({document:'verificationRequests/{uid}',region:options.region,retry:true}, async event => {
  const before = event.data.before.data(), after = event.data.after.data();
  if (before.status === after.status) return;
  await notify(event.params.uid, 'Verification updated', `Your business verification is ${after.status}.`, 'account', `verification_${event.id}`, {kind:'verification'});
});
exports.conversationAction = onCall(options, async request => {
 const a=await actor(request), ref=db.doc(`conversations/${id(request.data.conversationId)}`), action=request.data.action;
 await db.runTransaction(async tx=>{
  const c=data(await tx.get(ref)); if(!c.participants.includes(a.uid))fail('Not a participant.','permission-denied');
  if(action==='read')tx.update(ref,{[`readAt.${a.uid}`]:now(),[`unread.${a.uid}`]:0});
  else if(action==='hide')tx.update(ref,{hiddenBy:FieldValue.arrayUnion(a.uid)});
  else if(action==='block')tx.update(ref,{blockedBy:FieldValue.arrayUnion(a.uid)});
  else if(action==='unblock')tx.update(ref,{blockedBy:FieldValue.arrayRemove(a.uid)});
  else fail('Unsupported conversation action.');
 });return {ok:true};
});
const {onDocumentWritten} = require('firebase-functions/v2/firestore');
exports.publicProfile = onDocumentWritten({document:'users/{uid}',region:options.region},async event=>{
 const ref=db.doc(`publicProfiles/${event.params.uid}`);
 if(!event.data.after.exists){await ref.delete();return;}
 const p=event.data.after.data();await ref.set({name:p.name ?? '',role:p.role ?? null,location:p.location ?? '',verified:p.verified===true,suspended:p.suspended===true,featured:p.featured===true && p.verified===true && p.suspended!==true});
});


exports.acceptJob = onCall(options,async request=>{
 const a=await actor(request,'logistics'),ref=db.doc(`orders/${id(request.data.orderId)}`);
 await db.runTransaction(async tx=>{const o=data(await tx.get(ref));if(o.transporterId!==a.uid)fail('Not your job.','permission-denied');if(!['confirmed','ready'].includes(o.status))fail('Job unavailable.');tx.update(ref,{driverAccepted:true,updatedAt:now()});});return {ok:true};
});
exports.submitDeliveryProof = onCall(options,async request=>{
 const a=await actor(request),orderId=id(request.data.orderId),path=text(request.data.path,500),ref=db.doc(`orders/${orderId}`);
 if(!path.startsWith(`deliveries/${orderId}/${a.uid}/`) || path.split('/').length!==4)fail('Invalid proof location.');
 const [metadata]=await require('firebase-admin/storage').getStorage().bucket().file(path).getMetadata();
 if(metadata.contentType!=='image/jpeg' || Number(metadata.size)>5*1024*1024)fail('Invalid proof image.');
 await db.runTransaction(async tx=>{const o=data(await tx.get(ref));if((o.transporterId||o.supplierId)!==a.uid)fail('Only the delivery party may submit proof.','permission-denied');if(o.status!=='inTransit')fail('Delivery is not in transit.');tx.update(ref,{proofPath:path,updatedAt:now()});});return {ok:true};
});


