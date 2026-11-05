local mode=require('installation_mode')
assert(mode=='guidance','Unsupported missile installation mode')
return {missile_mode=mode,acceptance_recording=true,msl_visuals=false}
