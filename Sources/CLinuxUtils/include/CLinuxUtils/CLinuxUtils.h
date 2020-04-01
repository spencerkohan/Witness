//
//  CLinuxUtils.h
//  CLinuxUtils
//
//  Created by Spencer Kohan on 3/31/20.
//

#ifndef CLinuxUtils_h
#define CLinuxUtils_h
#ifdef __linux__

#include <stdint.h>

char* getEventName(void* event);
uint32_t getEventStride(void* event);

#endif
#endif /* CLinuxUtils_h */
