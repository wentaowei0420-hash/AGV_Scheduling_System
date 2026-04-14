cd('D:/pycharm_pro/AGV_Scheduling_System/AGV_Scheduling_System/ui_windows/matlab_code');
load('smallmap_fixed_20x20.mat','grid_map','cell_id_map');
ids = [223 224 225 226 228 229 230 243 244 245 246 247 248 249 250 263 264 265 266 267 268 269 270 284 285 286 287 288 289 290];
rcs = zeros(numel(ids),2);
for i=1:numel(ids)
 [r,c]=find(cell_id_map==ids(i)); rcs(i,:)=[r,c];
end
free_mask = false(1,numel(ids));
for i=1:numel(ids)
 free_mask(i) = (grid_map(rcs(i,1),rcs(i,2))==0);
end
ids = ids(free_mask); rcs = rcs(free_mask,:);
adj = cell(1,numel(ids));
for i=1:numel(ids)
  tmp=[];
  for j=1:numel(ids)
    if i~=j && sum(abs(rcs(i,:)-rcs(j,:)))==1
      tmp(end+1)=j; %#ok<AGROW>
    end
  end
  adj{i}=tmp;
end
paths = {};
for i=1:numel(ids)
  for ia=1:numel(adj{i})
    a=adj{i}(ia);
    for ib=1:numel(adj{a})
      b=adj{a}(ib);
      if b==i, continue; end
      for ic=1:numel(adj{b})
        c=adj{b}(ic);
        if c==a, continue; end
        paths{end+1}=[i a b c]; %#ok<AGROW>
      end
    end
  end
end
fprintf('paths=%d\n', numel(paths));
found = false;
for p1=1:numel(paths)
 for p2=1:numel(paths)
  if p2==p1, continue; end
  for p3=1:numel(paths)
   if p3==p1 || p3==p2, continue; end
   seq1=paths{p1}; seq2=paths{p2}; seq3=paths{p3};
   if numel(unique([seq1(1) seq2(1) seq3(1)]))<3, continue; end
   [d1,bb1]=first_conflict(seq1, seq2, seq3, [2 3]);
   [d2,bb2]=first_conflict(seq2, seq1, seq3, [1 3]);
   [d3,bb3]=first_conflict(seq3, seq1, seq2, [1 2]);
   if d1 && d2 && d3 && bb1==2 && bb2==3 && bb3==1
      fprintf('FOUND\n');
      disp(ids(seq1));
      disp(ids(seq2));
      disp(ids(seq3));
      found = true;
      return;
   end
  end
 end
end
if ~found
 fprintf('none found\n');
end
function [detected, blocker_agv] = first_conflict(selfSeq, other1, other2, agv_ids)
  detected=false; blocker_agv=0;
  nodeMap = containers.Map('KeyType','char','ValueType','double');
  edgeMap = containers.Map('KeyType','char','ValueType','double');
  others = {other1, other2};
  for o=1:2
    seq=others{o};
    curr=seq(1);
    key=sprintf('%d_%d',curr,10);
    if ~isKey(nodeMap,key), nodeMap(key)=agv_ids(o); end
    for k=2:numel(seq)
      t=10+(k-2);
      to=seq(k); from=seq(k-1);
      key=sprintf('%d_%d',to,t);
      if ~isKey(nodeMap,key), nodeMap(key)=agv_ids(o); end
      ekey=sprintf('%d_%d_%d',from,to,t);
      if ~isKey(edgeMap,ekey), edgeMap(ekey)=agv_ids(o); end
    end
  end
  for k=2:numel(selfSeq)
    t=10+(k-2);
    to=selfSeq(k); from=selfSeq(k-1);
    key=sprintf('%d_%d',to,t);
    if isKey(nodeMap,key)
      detected=true; blocker_agv=nodeMap(key); return;
    end
    ekey=sprintf('%d_%d_%d',to,from,t);
    if isKey(edgeMap,ekey)
      detected=true; blocker_agv=edgeMap(ekey); return;
    end
  end
end
