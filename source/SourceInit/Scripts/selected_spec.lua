-- Clone the selected patch set; the pinned original specification stays immutable.
local original=require('source_spec')
local mode=require('config').missile_mode
assert(mode=='guidance','Unsupported missile mode')
local values=require('guidance_values')
local counts={MSL=5,QAAM=2,SAAM=3,['2AAM']=1,['4AAM']=2,['6AAM']=2,HCAA=5,HPAA=3,HVAA=2,LAAM=3,SASM=2,STORY=1,EASY=1}
for key in pairs(counts)do
 local v=values[key]
 assert(type(v)=='number' and v==v and v>=0 and v<=1,'Invalid guidance value: '..key)
end
for key in pairs(values)do assert(counts[key],'Unknown guidance value: '..tostring(key))end
local patches,seen={},{}
local total=0
for _,patch in ipairs(original.patches)do
 local playerLead=patch.field=='HomingForesightAmount' and patch.row:match('^BP_plwp_')
 if not playerLead and patch.field=='HomingForesightAmount' then
  local p={row=patch.row,field=patch.field,before=patch.before,after=patch.after}
  if p.field=='HomingForesightAmount' then
   local token=p.row=='table:C.STORY' and 'STORY' or p.row=='table:EASY' and 'EASY' or p.row:match('^BP_plwp_([a-z0-9]+)_[a-z0-9]+$')
   token=token and token:upper()
   assert(token and counts[token],'Unknown guidance profile: '..p.row)
   p.after=values[token]
   seen[token]=(seen[token] or 0)+1
   total=total+1
  end
  patches[#patches+1]=p
 end
end
assert(total==2,'Guidance specification changed; validate before installation')
for _,key in ipairs({'STORY','EASY'})do assert(seen[key]==1,'Difficulty profile count changed: '..key)end
assert(#patches==2,'Selected patch count changed')
return {profiles=original.profiles,tablePath=original.tablePath,patches=patches}
