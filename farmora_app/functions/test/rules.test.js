'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc,setDoc,getDoc,updateDoc,serverTimestamp,collection,getDocs,query,where} = require('firebase/firestore');
const enabled = !!process.env.FIRESTORE_EMULATOR_HOST;
test('Firestore role, ownership, message privacy and financial write boundaries', {skip:!enabled}, async () => {
 const env = await initializeTestEnvironment({projectId:'demo-farmora',firestore:{rules:fs.readFileSync('../firestore.rules','utf8')}});
 try {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async ctx => {
   const db=ctx.firestore();
   for(const [uid,role] of [['buyer','buyer'],['supplier','supplier'],['stranger','buyer'],['driver','logistics']]) await setDoc(doc(db,'users',uid),{name:uid,role,suspended:false,verified:false});
   await setDoc(doc(db,'conversations','private'),{participants:['buyer','supplier'],updatedAt:serverTimestamp()});
   await setDoc(doc(db,'conversations','private','messages','m1'),{senderId:'supplier',text:'private',createdAt:serverTimestamp()});
   await setDoc(doc(db,'orders','order1'),{buyerId:'buyer',supplierId:'supplier',participants:['buyer','supplier'],status:'confirmed',paymentStatus:'pending'});
  });
  const buyer=env.authenticatedContext('buyer').firestore(),supplier=env.authenticatedContext('supplier').firestore(),stranger=env.authenticatedContext('stranger').firestore(),anon=env.unauthenticatedContext().firestore();
  const product={ownerId:'supplier',name:'Maize',location:'Harare',description:'Grade A',quantity:10,unit:'tonne',images:[],category:'Maize and grains',price:250,minimum:1,status:'active',createdAt:serverTimestamp(),updatedAt:serverTimestamp()};
  await assertSucceeds(setDoc(doc(supplier,'products','p1'),product));
  await assertFails(setDoc(doc(buyer,'products','fake'),{...product,ownerId:'buyer'}));
  await assertFails(updateDoc(doc(stranger,'products','p1'),{price:1,updatedAt:serverTimestamp()}));
  await assertFails(updateDoc(doc(supplier,'users','supplier'),{verified:true}));
  await assertFails(updateDoc(doc(buyer,'users','buyer'),{role:'supplier'}));
  await assertFails(updateDoc(doc(buyer,'orders','order1'),{paymentStatus:'paid'}));
  await assertFails(updateDoc(doc(supplier,'orders','order1'),{status:'completed'}));
  await assertSucceeds(getDoc(doc(buyer,'conversations','private','messages','m1')));
  await assertFails(getDoc(doc(stranger,'conversations','private','messages','m1')));
  await assertFails(getDoc(doc(anon,'products','p1')));
  await assertSucceeds(getDocs(query(collection(buyer,'orders'),where('participants','array-contains','buyer'))));
  await assertFails(getDocs(collection(stranger,'orders')));
  await assertFails(setDoc(doc(buyer,'conversations','private','messages','forged'),{senderId:'supplier',text:'fake',createdAt:serverTimestamp()}));
  await assertFails(setDoc(doc(supplier,'products','negative'),{...product,quantity:-1}));
  await assertFails(setDoc(doc(supplier,'products','adminfield'),{...product,verified:true}));
  assert.ok(true);
 } finally {await env.cleanup();}
});
