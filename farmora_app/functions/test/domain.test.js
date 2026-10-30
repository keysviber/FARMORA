'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {canTransition, positive, estimate} = require('../domain');
test('Only buyer can accept supplier quotation', () => {
 assert.equal(canTransition('quoted','confirmed','buyer'),true);
 for (const actor of ['supplier','logistics','admin',null]) assert.equal(canTransition('quoted','confirmed',actor),false);
});
test('Completed and cancelled orders cannot be resurrected', () => {
 for (const state of ['completed','cancelled','declined','disputed']) for (const role of ['buyer','supplier','logistics']) assert.equal(canTransition(state,'confirmed',role),false);
});
test('No skipped delivery states or transporter receipt confirmation', () => {
 assert.equal(canTransition('confirmed','completed','buyer'),false);
 assert.equal(canTransition('delivered','completed','logistics'),false);
 assert.equal(canTransition('delivered','completed','buyer'),true);
 assert.equal(canTransition('ready','inTransit','logistics'),true);
});
test('Transport estimate never accepts invalid route inputs', () => {
 assert.equal(estimate({roadKm:120,baseFee:0,rate:0.8}),96);
 assert.equal(estimate({roadKm:120,baseFee:10,rate:0.8,additional:5}),111);
 for (const roadKm of [-1,NaN,Infinity,'120']) assert.throws(() => estimate({roadKm,baseFee:0,rate:1}));
});
test('Positive numeric validation rejects strings, NaN and unbounded amounts', () => {
 for (const value of [0,-1,NaN,Infinity,'2',null,1e10]) assert.equal(positive(value),false);
 assert.equal(positive(0.5),true);
});
