//
//  CLinuxUtils.c
//  CLinuxUtils
//
//  Created by Spencer Kohan on 3/31/20.
//

#ifdef __linux__


#include "CLinuxUtils/CLinuxUtils.h"
#include <sys/inotify.h>
#include <stdio.h>
#include <stdlib.h>



char* getEventName(void* event) {
    return ((struct inotify_event*) event)->name;
}

uint32_t getEventStride(void* event) {
    struct inotify_event* e = (struct inotify_event*) event;
    return sizeof(struct inotify_event) + ((struct inotify_event*) e)->len;
}


#endif
