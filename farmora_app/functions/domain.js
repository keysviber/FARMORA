'use strict';
const transitions = {
  requested: {supplier: ['declined'], buyer: ['cancelled']},
  quoted: {buyer: ['confirmed', 'cancelled'], supplier: ['cancelled']},
  confirmed: {supplier: ['ready', 'cancelled'], buyer: ['cancelled']},
  ready: {supplier: ['inTransit', 'cancelled'], logistics: ['inTransit'], buyer: ['cancelled']},
  inTransit: {supplier: ['delivered', 'disputed'], logistics: ['delivered','deliveryFailed'], buyer: ['disputed']},
  delivered: {buyer: ['completed', 'disputed'], supplier: ['disputed']},
};
function canTransition(status, next, actor) { return transitions[status]?.[actor]?.includes(next) === true; }
function positive(value) { return typeof value === 'number' && Number.isFinite(value) && value > 0 && value <= 1e9; }
function estimate({roadKm, baseFee, rate, additional = 0}) {
  if ([roadKm, baseFee, rate, additional].some(v => typeof v !== 'number' || !Number.isFinite(v) || v < 0)) throw new Error('Invalid transport values');
  return Math.round((baseFee + roadKm * rate + additional) * 100) / 100;
}
module.exports = {canTransition, positive, estimate};

