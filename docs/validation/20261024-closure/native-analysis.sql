SELECT name, value, severity FROM stats
WHERE value != 0 AND name GLOB 'heapprofd*';

-- Deltas are cumulative only within this capture, not the pre-existing heap.
SELECT (ts - MIN(ts) OVER ())/1e9 AS seconds,
       SUM(size) AS delta_bytes,
       SUM(SUM(size)) OVER (ORDER BY ts) AS retained_since_start_bytes
FROM heap_profile_allocation GROUP BY ts;

WITH RECURSIVE
live AS (
  SELECT callsite_id, SUM(size) AS bytes FROM heap_profile_allocation
  GROUP BY callsite_id HAVING SUM(size)>0
),
chain(root,id,parent_id,frame_id,depth) AS (
  SELECT id,id,parent_id,frame_id,0 FROM stack_profile_callsite
  WHERE id IN (SELECT callsite_id FROM live)
  UNION ALL
  SELECT chain.root,c.id,c.parent_id,c.frame_id,chain.depth+1
  FROM chain JOIN stack_profile_callsite c ON c.id=chain.parent_id
  WHERE chain.depth<24
)
SELECT live.bytes,
       group_concat(f.name || ' @ ' || m.name || ' + ' || f.rel_pc, '; ') AS stack
FROM live JOIN chain ON chain.root=live.callsite_id
JOIN stack_profile_frame f ON f.id=chain.frame_id
JOIN stack_profile_mapping m ON m.id=f.mapping
GROUP BY live.callsite_id ORDER BY live.bytes DESC LIMIT 5;
