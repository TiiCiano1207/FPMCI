#include "src/free_look.h"
#include <cassert>
#include <cstdio>
using namespace flight;
int main(){
 for(float fov:{20.f,40.f,62.f,100.f,140.f})for(float dx:{-5.f,0.f,5.f})for(float dy:{-5.f,0.f,5.f}){
  auto view=basis(0,0,0);V aim=view.f;FreeLook head;head.step(true,aim,view,0,0,fov,62);
  auto actual=head.step(true,aim,view,dx,dy,fov,62);
  float ratio=std::tan(fov*.5f*rad)/std::tan(31*rad);
  assert(std::abs(actual.y/actual.x-dx*rad*ratio)<1e-5);
  assert(std::abs(actual.z/actual.x+dy*rad*ratio)<1e-5);
  assert(dot(aim,view.f)>.999999f);
  head.step(false,aim,view,500,500,fov,62);assert(dot(aim,view.f)>.999999f);
 }
 V aim{1,0,0};FreeLook head;auto nearPole=basis(88,0,0);head.step(true,aim,nearPole,0,0);
 auto top=head.step(true,aim,nearPole,0,-100);assert(pitch(top)>88.9&&std::abs(yaw(top))<.001);
 puts("PASS matched screen displacement across five FOVs, diagonal input, frozen flight goal, release boundary, pole limit");
}
