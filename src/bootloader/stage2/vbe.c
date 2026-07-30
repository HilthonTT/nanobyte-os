#include "vbe.h"
#include "x86.h"

bool VBE_GetControllerInfo(VbeInfoBlock *info)
{
  return x86_Video_GetVbeInfo(info) == 0;
}
