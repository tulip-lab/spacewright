import test from 'node:test';
import assert from 'node:assert/strict';
import { assertWorkspaceSpaceContinuity } from '../lib/finalization-policy.mjs';

function fixture() {
  const action = { type: 'remove_empty_space', spaceUuid: 'SLIDES', label: 'office_slides_tall', displayUuid: 'TALL' };
  return {
    plan: {
      workspaces: [{ workspaceId: 'slides', label: action.label, targetSpace: { uuid: 'SLIDES', label: action.label } }],
      selectedWindows: [], actions: [action]
    },
    snapshot: { spaces: [] },
    effects: [{ ...action, status: 'verified_success', postcondition: true }]
  };
}

test('tall continues to focus and verification after its inactive slides Space is cleaned', () => {
  const { plan, snapshot, effects } = fixture();
  assert.doesNotThrow(() => assertWorkspaceSpaceContinuity(plan, snapshot, effects));
});

for (const fault of ['unplanned', 'unjournaled', 'unknown', 'failed', 'unverified', 'other-space', 'other-display', 'other-label', 'active', 'relabeled']) {
  test(`cleanup continuity still rejects ${fault} Space disappearance or change`, () => {
    const { plan, snapshot, effects } = fixture();
    if (fault === 'unplanned') plan.actions = [];
    if (fault === 'unjournaled') effects.length = 0;
    if (fault === 'unknown') effects[0].status = 'attempted_unknown';
    if (fault === 'failed') effects[0].status = 'failed';
    if (fault === 'unverified') effects[0].postcondition = false;
    if (fault === 'other-space') effects[0].spaceUuid = 'OTHER';
    if (fault === 'other-display') effects[0].displayUuid = 'OTHER';
    if (fault === 'other-label') effects[0].label = 'OTHER';
    if (fault === 'active') plan.selectedWindows.push({ workspaceId: 'slides', id: 10 });
    if (fault === 'relabeled') snapshot.spaces.push({ uuid: 'SLIDES', label: 'personal' });
    assert.throws(() => assertWorkspaceSpaceContinuity(plan, snapshot, effects), /planned Space disappeared or its label changed/);
  });
}

test('an unplanned newly appearing target still blocks execution', () => {
  const { plan, snapshot } = fixture();
  plan.workspaces[0].targetSpace = null;
  snapshot.spaces.push({ uuid: 'NEW', label: 'office_slides_tall', display: 1 });
  snapshot.displays=[{index:1,uuid:'TALL'}];
  assert.throws(() => assertWorkspaceSpaceContinuity(plan, snapshot), /target Space appeared/);
  assert.doesNotThrow(() => assertWorkspaceSpaceContinuity(plan, snapshot, [{ type: 'ensure_space', workspaceId: 'slides',targetDisplayUuid:'TALL',status:'verified_success',postcondition:{createdSpaceUuid:'NEW',targetDisplayUuid:'TALL'} }]));
});


for(const fault of ['unjournaled','failed','unknown','other-space','other-display','missing-proof'])test(`new target continuity rejects ${fault} creation evidence`,()=>{
  const {plan,snapshot}=fixture();plan.workspaces[0].targetSpace=null;
  snapshot.spaces.push({uuid:'NEW',label:'office_slides_tall',display:1});
  snapshot.displays=[{index:1,uuid:'TALL'}];
  const effect={type:'ensure_space',workspaceId:'slides',targetDisplayUuid:'TALL',status:'verified_success',postcondition:{createdSpaceUuid:'NEW',targetDisplayUuid:'TALL'}};
  const effects=[effect];
  assert.doesNotThrow(()=>assertWorkspaceSpaceContinuity(plan,snapshot,effects));
  if(fault==='unjournaled')effects.length=0;
  if(fault==='failed')effect.status='failed';
  if(fault==='unknown')effect.status='attempted_unknown';
  if(fault==='other-space')effect.postcondition.createdSpaceUuid='OTHER';
  if(fault==='other-display')effect.postcondition.targetDisplayUuid='OTHER';
  if(fault==='missing-proof')effect.postcondition=true;
  assert.throws(()=>assertWorkspaceSpaceContinuity(plan,snapshot,effects),/target Space appeared/);
});
