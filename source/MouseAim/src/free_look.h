#pragma once
#include "flight_math.h"
namespace flight {
struct FreeLook {
    bool held=false,relative=false;
    V direction{1,0,0},local_direction{1,0,0};
    void reset() { held=relative=false; }
    V with_body(const Basis& body) const {return unit(body.f*local_direction.x+body.r*local_direction.y+body.u*local_direction.z);}
    V step(bool down, V& aim, const Basis& view, float dx, float dy,float fov=62,float reference_fov=62,V offset={},const Basis* body=nullptr) {
        // Discard boundary-frame deltas so release cannot move the flight target.
        if (down!=held || (down&&relative!=(body!=nullptr))) {
            held=down;
            relative=body!=nullptr;
            if (held){
                direction=view.f;
                if(relative)local_direction=unit({dot(direction,body->f),dot(direction,body->r),dot(direction,body->u)});
            }
            dx=dy=0;
        }
        if (held) {
            // Match the ring's screen-space/FOV conversion around the current head direction.
            V current=relative?local_direction:direction;
            const float p=pitch(current);
            const float scale=std::tan(std::clamp(fov,15.f,150.f)*.5f*rad)/std::tan(std::clamp(reference_fov,30.f,150.f)*.5f*rad);
            const float dp=std::clamp(-std::atan(dy*rad*scale)/rad,-89.f-p,89.f-p);
            dy=-std::tan(dp*rad)/(rad*scale);
            V moved=move_world_target(current,basis(pitch(current),yaw(current),0),dx,dy,fov,reference_fov);
            moved=basis(std::clamp(pitch(moved),-89.0f,89.0f),yaw(moved),0).f;
            if(relative){local_direction=moved;direction=with_body(*body);}
            else direction=moved;
            return direction;
        }
        aim=move_world_target(aim,view,dx,dy,fov,reference_fov,offset);
        return aim;
    }
};
}
