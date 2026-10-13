// Pure adapter geometry: planning and verification use the same per-object grid.
// App launch/reopen/native fullscreen recovery remains in explicit Fish adapters;
// it requires rediscovery and a new plan before identities can be selected.
export function roleGrid(workspace, role, selected, index, roleSelections = {}) {
  const configured = workspace.layout.find((item) => item.role === role)?.grid;
  const count = selected.length;
  if (workspace.runner === 'gtd_support' && role === 'dia') {
    if (workspace.mode === 'wide') {
      const left = Math.ceil(count / 2); const right = count - left;
      return index < left ? `${left}:2:0:${index}:1:1` : `${right}:2:1:${index - left}:1:1`;
    }
    if (workspace.mode === 'solo') {
      if (count === 1) return '1:1:0:0:1:1';
      if (count === 2) return `2:1:0:${index}:1:1`;
      if (count === 3) return ['2:2:0:0:1:1', '2:2:1:0:1:1', '2:1:0:1:1:1'][index];
    }
    if (workspace.mode === 'tall' && count <= 4) {
      const parts = (configured || '2:1:0:1:1:1').split(':').map(Number);
      const rows = parts[0], split = parts[3] || rows / 2, bottom = parts[5];
      const top = `${rows}:1:0:0:1:${split}`, low = `${rows}:1:0:${split}:1:${bottom}`;
      if (count === 1) return low;
      if (count === 2) return [top, low][index];
      const topColumns = [`${rows}:2:0:0:1:${split}`, `${rows}:2:1:0:1:${split}`];
      if (count === 3) return [...topColumns, low][index];
      return [...topColumns, `${rows}:2:0:${split}:1:${bottom}`, `${rows}:2:1:${split}:1:${bottom}`][index];
    }
    return `${Math.ceil(count / 2)}:2:${index % 2}:${Math.floor(index / 2)}:1:1`;
  }
  if (workspace.runner === 'office_document') {
    const primaryCount = roleSelections.primary?.length || (role === 'primary' ? count : 0);
    const helper = Boolean(roleSelections.helper?.length);
    const top = workspace.layout.find((r) => r.role === 'helper')?.grid || '2:1:0:0:1:1';
    const bottom = workspace.layout.find((r) => r.role === 'primary')?.grid || '2:1:0:1:1:1';
    const column = (grid, col) => { const p = grid.split(':'); return `${p[0]}:2:${col}:${p[3]}:1:${p[5]}`; };
    if (role === 'helper') return workspace.mode === 'tall' ? (primaryCount <= 1 ? top : column(top, 0)) : workspace.mode === 'solo' ? '1:3:2:0:1:1' : '1:3:0:0:1:1';
    if (role === 'primary') {
      if (workspace.mode === 'tall') {
        if (helper) return count === 1 ? bottom : count === 2 ? [column(top, 1), bottom][index] : count === 3 ? [column(top, 1), column(bottom, 0), column(bottom, 1)][index] : `${count}:1:0:${index}:1:1`;
        return count === 1 ? '1:1:0:0:1:1' : count === 2 ? [top, bottom][index] : count <= 4 ? [column(top, 0), column(top, 1), column(bottom, 0), column(bottom, 1)][index] : `${count}:1:0:${index}:1:1`;
      }
      if (!helper) return `1:${count}:${index}:0:1:1`;
      const offset = workspace.mode === 'wide' ? 1 : 0;
      if (count === 1) return `1:3:${offset}:0:2:1`;
      if (count === 2) return `1:3:${offset + index}:0:1:1`;
      if (count === 3) return index === 0 ? `1:3:${offset}:0:1:1` : `2:3:${offset + 1}:${index - 1}:1:1`;
      return `${count}:3:${offset}:${index}:2:1`;
    }
  }
  if (workspace.runner === 'primary_helper' && role === 'primary' && !roleSelections.helper?.length) {
    return workspace.primaryAloneLayout?.find((item) => item.role === role)?.grid || configured;
  }
  return configured;
}
