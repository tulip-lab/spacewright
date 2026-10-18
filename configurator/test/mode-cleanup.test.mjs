import test from 'node:test';
import assert from 'node:assert/strict';
import { compareState, buildExecutionPlan, normalizeSnapshot } from '../lib/state-engine.mjs';
import { executePinnedCleanup } from '../lib/pinned-executor.mjs';

function fixture({ policy = 'all', leadingHome = false } = {}) {
  const spaces = [
    ...(leadingHome ? [{uuid:'HOME',label:''}] : []),
    {uuid:'CODE',label:'code_tall'},
    {uuid:'BLANK-1',label:''},
    {uuid:'BLANK-2',label:''},
    {uuid:'MAIL',label:'mail_tall'},
    {uuid:'PERSONAL',label:'personal'}
  ].map((s,i)=>({...s,index:i+1,display:1,type:'float'}));
  spaces.push({uuid:'ONLY',label:'',index:spaces.length+1,display:2,type:'float'});
  const windows = ['CODE','MAIL'].map((uuid,i)=>({id:i+10,pid:i+100,processFingerprint:`process-${i}`,
    app:uuid,space:spaces.find(s=>s.uuid===uuid).index,display:1,role:'AXWindow',subrole:'AXStandardWindow',
    frame:{x:0,y:0,w:1000,h:900},'can-move':true,'can-resize':true}));
  const snapshot=normalizeSnapshot({displays:[
    {uuid:'PRIMARY',index:1,frame:{x:0,y:0,w:1000,h:1800}},
    {uuid:'SECONDARY',index:2,frame:{x:1000,y:0,w:1000,h:1800}}
  ],spaces,windows});
  const desired={desiredStateId:'cleanup',target:{kind:'mode',id:'tall',mode:'tall'},cleanupEmptySpaces:policy,
    workspaces:['code','mail'].map(id=>({workspaceId:id,label:`${id}_tall`,displayRole:'primary',
      runner:'generic_layout',windows:[],layout:[]}))};
  const machine={displayBindings:{primary:'PRIMARY'}};
  const plan=()=>buildExecutionPlan(snapshot,desired,compareState(snapshot,desired,machine));
  return {snapshot,desired,machine,plan};
}

test('all cleanup removes middle blank Spaces without reserving a false Home or rearranging correct workspaces',async()=>{
  const f=fixture(),plan=f.plan();
  const removals=plan.actions.filter(a=>a.type==='remove_empty_space');
  assert.deepEqual(removals.map(a=>a.spaceUuid),['BLANK-2','BLANK-1']);
  assert.deepEqual(plan.runnerCommands,[['finalize','tall']]);
  assert.equal(plan.actions.some(a=>a.type==='order_spaces'),false);
  const removed=[];
  await executePinnedCleanup(plan,{
    discover:async()=>({...f.snapshot,capturedAt:new Date().toISOString()}),
    mutate:async(args,intent,verify)=>{
      const space=f.snapshot.spaces.find(s=>s.index===Number(args[2]));
      assert.equal(space.uuid,intent.spaceUuid);
      removed.push(space.uuid);
      f.snapshot.spaces=f.snapshot.spaces.filter(s=>s.uuid!==space.uuid);
      for(const s of f.snapshot.spaces)if(s.index>space.index)s.index--;
      for(const w of f.snapshot.windows)if(w.space>space.index)w.space--;
      assert.equal(verify(f.snapshot),true);
    }
  });
  assert.deepEqual(removed,['BLANK-2','BLANK-1']);
  assert.deepEqual(f.snapshot.spaces.map(s=>s.uuid),['CODE','MAIL','PERSONAL','ONLY']);
  assert.equal(compareState(f.snapshot,f.desired,f.machine).converged,true);
});

test('all cleanup retains a genuine leading Home and the last Space on another display',()=>{
  const f=fixture({leadingHome:true});
  assert.deepEqual(f.plan().actions.filter(a=>a.type==='remove_empty_space').map(a=>a.spaceUuid),['BLANK-2','BLANK-1']);
});

for(const policy of ['managed','none'])test(`${policy} cleanup still preserves unlabeled user Spaces`,()=>{
  assert.deepEqual(fixture({policy}).plan().actions.filter(a=>a.type==='remove_empty_space'),[]);
});

test('an occupied middle blank Space is retained, including a minimized window',()=>{
  const f=fixture();
  f.snapshot.windows.push({...f.snapshot.windows[0],id:99,space:f.snapshot.spaces.find(s=>s.uuid==='BLANK-1').index,minimized:true});
  assert.deepEqual(f.plan().actions.filter(a=>a.type==='remove_empty_space').map(a=>a.spaceUuid),['BLANK-2']);
});
