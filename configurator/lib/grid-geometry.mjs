// yabai's grid first constrains display bounds, then applies view padding and
// edge-dependent gaps before dividing cells (window_manager_apply_grid).
// https://github.com/koekeishiya/yabai/blob/master/src/window_manager.c
export function gridFrame(display, value) {
  const p = String(value || '').split(':').map(Number);
  if(p.length!==6 || !p.every(Number.isFinite))return null;
  const [rows,cols,requestedX,requestedY,requestedW,requestedH]=p;
  if(!p.every(Number.isInteger) || rows<=0 || cols<=0 || requestedX<0 || requestedY<0 || requestedW<0 || requestedH<0)return null;
  // yabai clamps coordinates and spans before applying padding/gaps. Existing
  // adapter grids intentionally extend beyond an edge, so compare the clamped
  // result rather than rejecting a valid backend command.
  const x=Math.min(requestedX,cols-1),y=Math.min(requestedY,rows-1);
  const w=Math.min(Math.max(requestedW,1),cols-x),h=Math.min(Math.max(requestedH,1),rows-y);
  const g=display?.gridGeometry;
  const f=g?.frame || display?.frame;
  if(!f?.w || !f?.h)return null;
  const padding=g?.padding || {top:0,bottom:0,left:0,right:0}, gap=g?.gap || 0;
  const left=padding.left+(x>0?gap:0), top=padding.top+(y>0?gap:0);
  const width=f.w-left-padding.right-(cols>x+w?gap:0);
  const height=f.h-top-padding.bottom-(rows>y+h?gap:0);
  return {x:f.x+left+width*x/cols,y:f.y+top+height*y/rows,w:width*w/cols,h:height*h/rows};
}
