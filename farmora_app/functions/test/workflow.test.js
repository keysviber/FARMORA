'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore,FieldValue}=require('firebase-admin/firestore');
const enabled=!!process.env.FIRESTORE_EMULATOR_HOST && !!process.env.FIREBASE_AUTH_EMULATOR_HOST;
test('Real callable workflow prevents overselling, deduplicates orders, controls delivery and payments', {skip:!enabled,timeout:120000}, async()=>{
 const app=initializeApp({projectId:'demo-farmora'},'workflow-tests'), db=getFirestore(app);
 const suffix=Date.now().toString();
 async function account(role,index){
  const response=await fetch(`http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-key`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:`${role}${index}${suffix}@example.test`,password:'Testing123!',returnSecureToken:true})});
  const auth=await response.json();assert.ok(auth.idToken,JSON.stringify(auth));
  await db.doc(`users/${auth.localId}`).set({name:role,role,suspended:false,verified:false,location:'Harare'});
  return {uid:auth.localId,token:auth.idToken};
 }
 async function call(user,name,data){
  const response=await fetch(`http://127.0.0.1:5001/demo-farmora/africa-south1/${name}`,{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${user.token}`},body:JSON.stringify({data})});
  const result=await response.json();return result;
 }
 try{
  const supplier=await account('supplier',1), buyer=await account('buyer',1), other=await account('buyer',2), driver=await account('logistics',1);
  const productId=`p${suffix}`;
  await db.doc(`products/${productId}`).set({ownerId:supplier.uid,name:'Maize',quantity:10,unit:'tonne',minimum:1,price:250,status:'active',location:'Harare',createdAt:FieldValue.serverTimestamp()});
  const args={productId,quantity:8,destination:'Bulawayo',requestKey:`key${suffix}`};
  const first=await call(buyer,'requestOrder',args);assert.ok(first.result,JSON.stringify(first));
  const retry=await call(buyer,'requestOrder',args);assert.equal(first.result.id,retry.result.id);
  const second=await call(other,'requestOrder',args);assert.ok(second.result,JSON.stringify(second));
  const orderId=first.result.id;
  assert.ok((await call(other,'quoteOrder',{orderId,price:200})).error);
  assert.ok((await call(supplier,'quoteOrder',{orderId,price:250})).result);
  assert.ok((await call(supplier,'quoteOrder',{orderId:second.result.id,price:250})).result);
  const accepts=await Promise.all([call(buyer,'transitionOrder',{orderId,next:'confirmed'}),call(other,'transitionOrder',{orderId:second.result.id,next:'confirmed'})]);
  assert.equal(accepts.filter(r=>r.result).length,1,JSON.stringify(accepts));
  assert.equal((await db.doc(`products/${productId}`).get()).data().quantity,2);
  const winner=accepts[0].result?buyer:other, winnerId=accepts[0].result?orderId:second.result.id;
  assert.ok((await call(winner,'transitionOrder',{orderId:winnerId,next:'confirmed'})).result);
  assert.equal((await db.doc(`products/${productId}`).get()).data().quantity,2);
  assert.ok((await call(winner,'transitionOrder',{orderId:winnerId,next:'completed'})).error);
  assert.ok((await call(winner,'requestTransport',{orderId:winnerId})).result);
  await db.doc(`vehicles/v${suffix}`).set({ownerId:driver.uid,status:'active',quantity:20,unit:'tonne',name:'Truck',rate:1,baseFee:10});
  const quote=await call(driver,'submitTransportQuote',{requestId:winnerId,amount:100});assert.ok(quote.result,JSON.stringify(quote));
  assert.ok((await call(winner,'acceptTransportQuote',{quoteId:quote.result.id})).result);
  assert.ok((await call(driver,'acceptJob',{orderId:winnerId})).result);
  assert.ok((await call(supplier,'transitionOrder',{orderId:winnerId,next:'ready'})).result);
  assert.ok((await call(supplier,'transitionOrder',{orderId:winnerId,next:'inTransit'})).error);
  assert.ok((await call(driver,'transitionOrder',{orderId:winnerId,next:'inTransit'})).result);
  assert.ok((await call(winner,'recordPayment',{orderId:winnerId,reference:'Bank transfer reference TEST'})).result);
  assert.equal((await db.doc(`orders/${winnerId}`).get()).data().paymentStatus,'awaitingVerification');
  assert.ok((await call(driver,'transitionOrder',{orderId:winnerId,next:'delivered'})).error);
  await db.doc('orders/'+winnerId).update({proofPath:'emulator-proof-fixture'});
  assert.ok((await call(driver,'transitionOrder',{orderId:winnerId,next:'delivered'})).result);
  assert.ok((await call(driver,'transitionOrder',{orderId:winnerId,next:'completed'})).error);
  assert.ok((await call(winner,'transitionOrder',{orderId:winnerId,next:'completed'})).result);
  // A second reserved order demonstrates cancellation restores stock only once.
  const cancellation=await call(buyer,'requestOrder',{...args,quantity:2,requestKey:`cancel${suffix}`});
  const cancelId=cancellation.result.id;
  await call(supplier,'quoteOrder',{orderId:cancelId,price:250});
  await call(buyer,'transitionOrder',{orderId:cancelId,next:'confirmed'});
  await call(buyer,'transitionOrder',{orderId:cancelId,next:'cancelled'});
  await call(buyer,'transitionOrder',{orderId:cancelId,next:'cancelled'});
  assert.equal((await db.doc(`products/${productId}`).get()).data().quantity,2);
  const chat=await call(buyer,'startConversation',{collection:'products',recordId:productId});assert.ok(chat.result,JSON.stringify(chat));
  assert.ok((await call(other,'sendMessage',{conversationId:chat.result.id,text:'unauthorized'})).error);
  assert.ok((await call(buyer,'sendMessage',{conversationId:chat.result.id,text:'Is this available?'})).result);
  assert.ok((await call(supplier,'conversationAction',{conversationId:chat.result.id,action:'block'})).result);
  assert.ok((await call(buyer,'sendMessage',{conversationId:chat.result.id,text:'blocked'})).error);
 }finally{await deleteApp(app);}
});

